import 'dart:async';

import '../models.dart';
import 'groq_client.dart';
import 'tavily_client.dart';

/// Events the council emits while it works, so the chat UI can
/// animate each advisor as it thinks, speaks and reacts.
sealed class CouncilEvent {}

class EvidenceEvent extends CouncilEvent {
  EvidenceEvent(this.sources);
  final List<EvidenceSource> sources;
}

class AdvisorThinking extends CouncilEvent {
  AdvisorThinking(this.advisor);
  final Advisor advisor;
}

class OpinionEvent extends CouncilEvent {
  OpinionEvent(this.opinion);
  final Opinion opinion;
}

class AdvisorFailed extends CouncilEvent {
  AdvisorFailed(this.advisor, this.error);
  final Advisor advisor;
  final String error;
}

class ProgressEvent extends CouncilEvent {
  ProgressEvent(this.text);
  final String text;
}

class VerdictEvent extends CouncilEvent {
  VerdictEvent(this.verdict);
  final Verdict verdict;
}

/// How each advisor reacts once the peer review is in:
/// most first-place ranks → happy bounce (agree),
/// most last-place ranks → unimpressed (disagree).
class MoodsEvent extends CouncilEvent {
  MoodsEvent(this.moods);
  final Map<String, BlobMood> moods;
}

/// Runs the council: dynamic clarifying questions, then
/// Stage 1 (five independent opinions) → Stage 2 (anonymous peer
/// review) → Stage 3 (chairman's fixed-format verdict).
class CouncilService {
  CouncilService({required this.groq, this.tavily});

  final GroqClient groq;
  final TavilyClient? tavily;

  /// Ask Groq what it needs to know before judging. Returns 0-5
  /// questions — zero when the question is already clear.
  Future<List<ClarifyingQuestion>> generateQuestions(
    String question,
  ) async {
    final data = await groq.chatJson(
      messages: [
        {
          'role': 'system',
          'content':
              'You help a decision council ask clarifying questions before it judges. '
              'Read the user question and return ONLY questions whose answers would genuinely change the verdict. '
              'Ask at most 5, ask 0 if the question is already clear and specific. '
              'Prefer short, concrete questions. Give 2-4 quick tap-to-answer options when the answer is a simple choice, otherwise an empty options list. '
              'Reply as JSON: {"questions": [{"question": "...", "options": ["...", "..."]}]}',
        },
        {'role': 'user', 'content': question},
      ],
      temperature: 0.4,
      maxTokens: 800,
    );
    final list = data['questions'];
    if (list is! List) return [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ClarifyingQuestion.fromJson)
        .where((q) => q.question.trim().isNotEmpty)
        .take(5)
        .toList();
  }

  /// Runs the full council and yields events as it goes.
  Stream<CouncilEvent> run({
    required String question,
    required Map<String, String> answers,
    required DateTime askedAt,
  }) async* {
    final context = _buildContext(question, answers);

    // Live facts first, when a Tavily key is set. Never blocks the
    // council — a failed search just means no evidence pack.
    List<EvidenceSource> evidence = [];
    if (tavily != null) {
      yield ProgressEvent('Checking live facts…');
      try {
        evidence = await tavily!.search(question);
      } catch (_) {
        evidence = [];
      }
      yield EvidenceEvent(evidence);
    } else {
      yield EvidenceEvent([]);
    }
    final fullContext = evidence.isEmpty
        ? context
        : '$context\n\nLIVE FACTS (checked just now, ${askedAt.day}/${askedAt.month}/${askedAt.year}):\n${evidence.map((e) => '- ${e.title} (${e.date}): ${e.snippet} [${e.url}]').join('\n')}\nAdvisors must use these facts where relevant and say so; if they are thin, old or conflicting, confidence must be Low.';

    // Stage 1: five independent opinions, in parallel. Each
    // advisor's events stream out as its call finishes.
    yield ProgressEvent('The council is thinking…');
    final opinions = <Opinion>[];
    final controller = StreamController<CouncilEvent>();
    final tasks = Advisor.all
        .map((a) => _opinionTask(a, fullContext, controller, opinions))
        .toList();
    // Close the event stream once every advisor call has settled.
    unawaited(Future.wait(tasks).then((_) => controller.close()));
    yield* controller.stream;

    if (opinions.isEmpty) {
      throw const GroqException(
        'All five advisors failed to answer. Check your Groq key and connection, then try again.',
      );
    }

    // Stage 2: anonymous peer review, in parallel.
    yield ProgressEvent('Advisors are reviewing each other…');
    final reviews = await _peerReviews(opinions, fullContext);
    yield MoodsEvent(_moodsFromReviews(reviews, opinions));

    // Stage 3: chairman's verdict, fixed format.
    yield ProgressEvent('The chairman is deciding…');
    final verdict = await _chairmanVerdict(
      question: question,
      answers: answers,
      opinions: opinions,
      reviews: reviews,
      evidence: evidence,
    );
    yield VerdictEvent(verdict);
  }

  // -- internals ---------------------------------------------------

  Future<void> _opinionTask(
    Advisor advisor,
    String context,
    StreamController<CouncilEvent> out,
    List<Opinion> results,
  ) async {
    out.add(AdvisorThinking(advisor));
    try {
      final text = await _advisorOpinion(advisor, context);
      final opinion = Opinion(advisorId: advisor.id, text: text);
      results.add(opinion);
      out.add(OpinionEvent(opinion));
    } catch (e) {
      out.add(AdvisorFailed(advisor, e.toString()));
    }
  }

  String _buildContext(String question, Map<String, String> answers) {
    final buf = StringBuffer('USER QUESTION: $question');
    if (answers.isNotEmpty) {
      buf.writeln('\n\nWHAT THE USER TOLD THE COUNCIL:');
      answers.forEach((q, a) => buf.writeln('- $q → $a'));
    }
    return buf.toString();
  }

  Future<String> _advisorOpinion(Advisor advisor, String context) {
    return groq.chat(
      messages: [
        {
          'role': 'system',
          'content':
              'You are ${advisor.name}, a council advisor. Your job: ${advisor.job} '
              'Answer in 3-5 short sentences, in plain simple words. '
              'Be specific to the question and the context. Do not be sycophantic — '
              'if the idea is bad, say so plainly. Do not repeat the question back.',
        },
        {'role': 'user', 'content': context},
      ],
      temperature: 0.8,
      maxTokens: 500,
    );
  }

  Future<List<Review>> _peerReviews(
    List<Opinion> opinions,
    String context,
  ) async {
    final futures = <Future<Review?>>[];
    for (final reviewer in Advisor.all) {
      final others =
          opinions.where((o) => o.advisorId != reviewer.id).toList();
      if (others.isEmpty) continue;
      futures.add(_oneReview(reviewer, others, context));
    }
    final done = await Future.wait(futures);
    return done.whereType<Review>().toList();
  }

  Future<Review?> _oneReview(
    Advisor reviewer,
    List<Opinion> others,
    String context,
  ) async {
    // Opinions are numbered, never named — the review is blind.
    final numbered = others.asMap().entries.map((e) {
      final n = e.key + 1;
      return 'Opinion $n: ${e.value.text}';
    }).join('\n\n');
    try {
      final data = await groq.chatJson(
        messages: [
          {
            'role': 'system',
            'content':
                'You are ${reviewer.name}, reviewing other advisors\' opinions. '
                'You do not know who wrote them. Rank them best to worst by how useful and correct they are for the user question, '
                'and write one sharp sentence of critique for the weakest one. '
                'Reply as JSON: {"ranking": [2, 1, 4, 3], "critique": "..."} where the numbers are the opinion numbers.',
          },
          {
            'role': 'user',
            'content': '$context\n\nOPINIONS TO REVIEW:\n$numbered',
          },
        ],
        temperature: 0.5,
        maxTokens: 400,
      );
      final raw = data['ranking'];
      final rankingNums = raw is List
          ? raw
              .map((e) => int.tryParse(e.toString()) ?? 0)
              .where((n) => n >= 1 && n <= others.length)
              .toList()
          : <int>[];
      final ranking =
          rankingNums.map((n) => others[n - 1].advisorId).toList();
      return Review(
        reviewerId: reviewer.id,
        ranking: ranking,
        critique: (data['critique'] ?? '').toString(),
      );
    } catch (_) {
      return null; // A failed review never blocks the verdict.
    }
  }

  /// Most first-place peer ranks → agree, most last-place → disagree.
  Map<String, BlobMood> _moodsFromReviews(
    List<Review> reviews,
    List<Opinion> opinions,
  ) {
    final firsts = <String, int>{};
    final lasts = <String, int>{};
    for (final r in reviews) {
      if (r.ranking.isEmpty) continue;
      firsts[r.ranking.first] = (firsts[r.ranking.first] ?? 0) + 1;
      lasts[r.ranking.last] = (lasts[r.ranking.last] ?? 0) + 1;
    }
    final maxFirst =
        firsts.values.fold(0, (a, b) => a > b ? a : b);
    final maxLast = lasts.values.fold(0, (a, b) => a > b ? a : b);
    final moods = <String, BlobMood>{};
    for (final o in opinions) {
      final f = firsts[o.advisorId] ?? 0;
      final l = lasts[o.advisorId] ?? 0;
      if (f > 0 && f == maxFirst && f >= l) {
        moods[o.advisorId] = BlobMood.agree;
      } else if (l > 0 && l == maxLast && l > f) {
        moods[o.advisorId] = BlobMood.disagree;
      } else {
        moods[o.advisorId] = BlobMood.idle;
      }
    }
    return moods;
  }

  Future<Verdict> _chairmanVerdict({
    required String question,
    required Map<String, String> answers,
    required List<Opinion> opinions,
    required List<Review> reviews,
    required List<EvidenceSource> evidence,
  }) async {
    final opinionsText = opinions
        .map((o) => '${Advisor.byId(o.advisorId).name}: ${o.text}')
        .join('\n\n');
    final reviewsText = reviews.isEmpty
        ? 'No peer reviews completed.'
        : reviews
            .map(
              (r) =>
                  '${Advisor.byId(r.reviewerId).name} ranked best-first: ${r.ranking.map(Advisor.byId).map((a) => a.name).join(', ')}. Critique: ${r.critique}',
            )
            .join('\n');
    final data = await groq.chatJson(
      messages: [
        {
          'role': 'system',
          'content':
              'You are the Chairman of the council. You have read five independent opinions and their anonymous peer reviews. '
              'Give ONE decision. Do not smooth disagreement into a vague middle ground — if advisors clash, say so and keep the strongest objection. '
              'If the live facts are thin, old or conflicting, confidence must be Low. Never invent facts, numbers or sources. '
              'Reply as JSON only: {"decision": "Go" | "No-Go" | "Test first", "confidence": "Low" | "Medium" | "High", '
              '"why": "at most 2 lines", "biggest_risk": "...", "changes_mind": "what would change this verdict", '
              '"first_step": "one concrete step doable in about 15 minutes", "dissent": "the strongest objection, even if you disagree with it"}',
        },
        {
          'role': 'user',
          'content':
              '${_buildContext(question, answers)}\n\nOPINIONS:\n$opinionsText\n\nPEER REVIEWS:\n$reviewsText\n\nLIVE SOURCES: ${evidence.isEmpty ? 'none checked' : evidence.map((e) => e.url).join(', ')}',
        },
      ],
      temperature: 0.4,
      maxTokens: 800,
    );
    return Verdict.fromJson(data);
  }
}
