import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';
import '../services/council.dart';
import '../services/groq_client.dart';
import '../services/history_store.dart';
import '../services/settings_store.dart';
import '../services/tavily_client.dart';
import '../widgets/blob_avatar.dart';
import '../widgets/chat_bubbles.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

// -- chat items ----------------------------------------------------

sealed class _Item {}

class _UserItem extends _Item {
  _UserItem(this.text);
  final String text;
}

class _AdvisorItem extends _Item {
  _AdvisorItem(this.advisor, this.text, [this.mood = BlobMood.speaking]);
  final Advisor advisor;
  final String text;
  BlobMood mood;
}

class _TypingItem extends _Item {
  _TypingItem(this.advisor);
  final Advisor advisor;
}

class _QuestionItem extends _Item {
  _QuestionItem(this.question);
  final ClarifyingQuestion question;
}

class _ProgressItem extends _Item {
  _ProgressItem(this.text);
  String text;
}

class _EvidenceItem extends _Item {
  _EvidenceItem(this.sources);
  final List<EvidenceSource> sources;
}

class _VerdictItem extends _Item {
  _VerdictItem(this.verdict);
  final Verdict verdict;
}

class _ErrorItem extends _Item {
  _ErrorItem(this.text);
  final String text;
}

enum _Phase { idle, askingQuestions, running }

/// The Apple-like chat: blue bubbles on the right, grey advisor
/// bubbles on the left, verdict as a Chairman message.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _items = <_Item>[];
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _settings = SettingsStore();

  _Phase _phase = _Phase.idle;
  List<ClarifyingQuestion> _questions = [];
  int _questionIndex = 0;
  final _answers = <String, String>{};
  String _currentQuestion = '';
  final _opinions = <Opinion>[];
  List<EvidenceSource> _evidence = [];

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _add(_Item item) {
    setState(() => _items.add(item));
    _scrollToBottom();
  }

  void _replaceProgress(String text) {
    setState(() {
      for (var i = _items.length - 1; i >= 0; i--) {
        if (_items[i] is _ProgressItem) {
          (_items[i] as _ProgressItem).text = text;
          return;
        }
      }
      _items.add(_ProgressItem(text));
    });
    _scrollToBottom();
  }

  void _removeProgress() {
    setState(() => _items.removeWhere((i) => i is _ProgressItem));
  }

  // -- flow ----------------------------------------------------------

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      if (_phase == _Phase.askingQuestions) _skipCurrent();
      return;
    }
    _input.clear();
    if (_phase == _Phase.askingQuestions) {
      _answerCurrent(text);
      return;
    }
    if (_phase != _Phase.idle) return;
    await _startAsk(text);
  }

  Future<void> _startAsk(String question) async {
    _add(_UserItem(question));
    _currentQuestion = question;
    _answers.clear();
    _opinions.clear();
    _evidence = [];
    final groqKey = await _settings.groqKey;
    if (groqKey == null || groqKey.isEmpty) {
      _add(_ErrorItem(
        'No Groq API key yet. Add yours in Settings — it stays on your phone, never in code.',
      ));
      return;
    }
    setState(() => _phase = _Phase.askingQuestions);
    _add(_ProgressItem('The council is thinking…'));
    try {
      final council = await _buildCouncil(groqKey);
      final questions = await council.generateQuestions(question);
      _removeProgress();
      if (questions.isEmpty) {
        await _runCouncil(question, const {});
      } else {
        _questions = questions;
        _questionIndex = 0;
        _add(_QuestionItem(questions.first));
        _scrollToBottom();
      }
    } catch (e) {
      _removeProgress();
      setState(() => _phase = _Phase.idle);
      _add(_ErrorItem('Could not reach Groq: $e'));
    }
  }

  void _answerCurrent(String answer) {
    final q = _questions[_questionIndex];
    _answers[q.question] = answer;
    _add(_UserItem(answer));
    _nextQuestion();
  }

  void _skipCurrent() {
    _nextQuestion();
  }

  void _skipAll() {
    _runCouncil(_currentQuestion, _answers);
  }

  void _nextQuestion() {
    _questionIndex++;
    if (_questionIndex < _questions.length) {
      _add(_QuestionItem(_questions[_questionIndex]));
    } else {
      _runCouncil(_currentQuestion, _answers);
    }
  }

  Future<CouncilService> _buildCouncil(String groqKey) async {
    final model = await _settings.model;
    final tavilyKey = await _settings.tavilyKey;
    return CouncilService(
      groq: GroqClient(apiKey: groqKey, model: model),
      tavily: (tavilyKey != null && tavilyKey.isNotEmpty)
          ? TavilyClient(apiKey: tavilyKey)
          : null,
    );
  }

  Future<void> _runCouncil(
    String question,
    Map<String, String> answers,
  ) async {
    setState(() => _phase = _Phase.running);
    final groqKey = await _settings.groqKey;
    if (groqKey == null || groqKey.isEmpty) {
      setState(() => _phase = _Phase.idle);
      _add(_ErrorItem('No Groq API key yet. Add yours in Settings.'));
      return;
    }
    final council = await _buildCouncil(groqKey);
    Verdict? verdict;
    try {
      await for (final event in council.run(
        question: question,
        answers: Map.of(answers),
        askedAt: DateTime.now(),
      )) {
        if (!mounted) return;
        switch (event) {
          case ProgressEvent(:final text):
            _replaceProgress(text);
          case EvidenceEvent(:final sources):
            _evidence = sources;
            if (sources.isNotEmpty) {
              _add(_EvidenceItem(sources));
            }
          case AdvisorThinking(:final advisor):
            _add(_TypingItem(advisor));
          case OpinionEvent(:final opinion):
            _opinions.add(opinion);
            _swapTypingForOpinion(opinion);
          case AdvisorFailed(:final advisor):
            _swapTypingForFailure(advisor);
          case MoodsEvent(:final moods):
            setState(() {
              for (final item in _items) {
                if (item is _AdvisorItem &&
                    moods.containsKey(item.advisor.id)) {
                  item.mood = moods[item.advisor.id]!;
                }
              }
            });
          case VerdictEvent(verdict: final v):
            verdict = v;
            _removeProgress();
            _add(_VerdictItem(v));
        }
      }
      if (verdict != null) {
        await HistoryStore.saveRun(
          question: question,
          answers: answers,
          opinions: _opinions,
          verdict: verdict,
          evidence: _evidence,
        );
      }
    } catch (e) {
      _removeProgress();
      _add(_ErrorItem('The council hit a problem: $e'));
    } finally {
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  void _swapTypingForOpinion(Opinion opinion) {
    final advisor = Advisor.byId(opinion.advisorId);
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        final item = _items[i];
        if (item is _TypingItem && item.advisor.id == advisor.id) {
          _items[i] = _AdvisorItem(advisor, opinion.text, BlobMood.speaking);
          // Speaking settles back to idle after a beat.
          Timer(const Duration(milliseconds: 2500), () {
            if (!mounted) return;
            setState(() {
              final current = _items[i];
              if (current is _AdvisorItem &&
                  current.mood == BlobMood.speaking) {
                current.mood = BlobMood.idle;
              }
            });
          });
          break;
        }
      }
    });
    _scrollToBottom();
  }

  void _swapTypingForFailure(Advisor advisor) {
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        final item = _items[i];
        if (item is _TypingItem && item.advisor.id == advisor.id) {
          _items[i] = _AdvisorItem(
            advisor,
            'I couldn\'t answer this one — moving on.',
            BlobMood.confused,
          );
          break;
        }
      }
    });
    _scrollToBottom();
  }

  // -- UI ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F2F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'LLM Council',
          style: GoogleFonts.fraunces(
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New question',
            onPressed: () {
              setState(() {
                _items.clear();
                _phase = _Phase.idle;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? _Welcome(onExample: _startAsk)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: _items.length,
                    itemBuilder: (context, i) => _buildItem(_items[i]),
                  ),
          ),
          _InputBar(
            controller: _input,
            phase: _phase,
            onSend: _send,
            onSkip: _skipCurrent,
            onSkipAll: _skipAll,
          ),
        ],
      ),
    );
  }

  Widget _buildItem(_Item item) {
    return switch (item) {
      _UserItem(:final text) => UserBubble(text: text),
      _AdvisorItem(:final advisor, :final text, :final mood) =>
        AdvisorBubble(advisor: advisor, text: text, mood: mood),
      _TypingItem(:final advisor) => TypingBubble(advisor: advisor),
      _QuestionItem(:final question) => _QuestionCard(
          question: question,
          onOption: _answerCurrent,
          onSkip: _skipCurrent,
        ),
      _ProgressItem(:final text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              text,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ),
        ),
      _EvidenceItem(:final sources) => _EvidenceCard(sources: sources),
      _VerdictItem(:final verdict) => ChairmanBubble(verdict: verdict),
      _ErrorItem(:final text) => _ErrorCard(
          text: text,
          onSettings: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
        ),
    };
  }
}

/// One clarifying question, as a Council message with tap chips.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.onOption,
    required this.onSkip,
  });

  final ClarifyingQuestion question;
  final ValueChanged<String> onOption;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 52, bottom: 3),
            child: Text(
              'Council asks',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const ChairmanAvatar(size: 38),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE9E9EB),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question.question,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      if (question.options.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: question.options
                              .map(
                                (o) => ActionChip(
                                  label: Text(o),
                                  onPressed: () => onOption(o),
                                  backgroundColor: Colors.white,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: onSkip,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Skip this question',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Live sources the council checked, shown once per run.
class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.sources});

  final List<EvidenceSource> sources;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10, left: 48),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Checked ${sources.length} live sources',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final s in sources)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '• ${s.title}${s.date.isNotEmpty ? ' (${s.date})' : ''}\n  ${s.url}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.text, required this.onSettings});

  final String text;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE9E8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 14)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onSettings,
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

/// Empty-state: five blobs, the promise, and example questions.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.onExample});

  final ValueChanged<String> onExample;

  static const _examples = [
    'Should I quit my job to build my startup?',
    'Is now the right time to launch my app?',
    'Should I learn Flutter or React Native first?',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: Advisor.all
                .map(
                  (a) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: BlobAvatar(advisor: a, size: 46),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
          Text(
            'Ask the council.',
            style: GoogleFonts.fraunces(
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Five advisors argue it out.\nOne chairman gives you a verdict you can act on.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 24),
          for (final e in _examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                onPressed: () => onExample(e),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  e,
                  style: GoogleFonts.plusJakartaSans(fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// iMessage-style input bar. While questions are being asked it
/// answers them; while the council runs it waits.
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.phase,
    required this.onSend,
    required this.onSkip,
    required this.onSkipAll,
  });

  final TextEditingController controller;
  final _Phase phase;
  final VoidCallback onSend;
  final VoidCallback onSkip;
  final VoidCallback onSkipAll;

  @override
  Widget build(BuildContext context) {
    final busy = phase == _Phase.running;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        color: const Color(0xFFF2F2F7),
        child: Row(
          children: [
            if (phase == _Phase.askingQuestions)
              TextButton(
                onPressed: onSkipAll,
                child: const Text('Skip all'),
              ),
            Expanded(
              child: TextField(
                controller: controller,
                readOnly: busy,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: switch (phase) {
                    _Phase.askingQuestions => 'Answer, or tap Skip…',
                    _Phase.running => 'The council is working…',
                    _Phase.idle => 'Ask the council anything…',
                  },
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: busy ? null : onSend,
              child: CircleAvatar(
                backgroundColor:
                    busy ? Colors.grey.shade400 : const Color(0xFF007AFF),
                child: const Icon(
                  Icons.arrow_upward,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
