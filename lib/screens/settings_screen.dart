import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/groq_client.dart';
import '../services/settings_store.dart';

/// Keys live here and only here — in secure storage on the phone.
/// Nothing is ever hardcoded or sent anywhere except the API it
/// belongs to (Groq for the council, Tavily for live facts).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _store = SettingsStore();
  final _groqCtrl = TextEditingController();
  final _tavilyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();

  bool _groqSaved = false;
  bool _tavilySaved = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final groq = await _store.groqKey;
    final tavily = await _store.tavilyKey;
    final model = await _store.model;
    setState(() {
      _groqSaved = groq != null && groq.isNotEmpty;
      _tavilySaved = tavily != null && tavily.isNotEmpty;
      _modelCtrl.text = model;
    });
  }

  @override
  void dispose() {
    _groqCtrl.dispose();
    _tavilyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.fraunces(fontWeight: FontWeight.w700),
        ),
        backgroundColor: const Color(0xFFF2F2F7),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Groq API key',
            subtitle:
                'The council runs on Groq\'s free tier. Get a key at console.groq.com, paste it once — it stays in secure storage on this phone.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _groqCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: _groqSaved ? '•••••••• saved' : 'gsk_…',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        final v = _groqCtrl.text.trim();
                        if (v.isEmpty) return;
                        await _store.setGroqKey(v);
                        _groqCtrl.clear();
                        setState(() {
                          _groqSaved = true;
                          _testResult = null;
                        });
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Groq key saved.')),
                          );
                        }
                      },
                      child: const Text('Save key'),
                    ),
                    const SizedBox(width: 10),
                    if (_groqSaved)
                      TextButton(
                        onPressed: () async {
                          await _store.clearGroqKey();
                          setState(() => _groqSaved = false);
                        },
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Model',
            subtitle:
                'One model, five advisors. Check the Groq console that this model is still on the free tier — Groq moves models between tiers.',
            child: TextField(
              controller: _modelCtrl,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (v) async {
                if (v.trim().isNotEmpty) await _store.setModel(v);
              },
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Tavily key (optional)',
            subtitle:
                'For live facts. Tavily gives 1,000 free credits a month, no card. Without it the council judges from the model\'s own knowledge and says so.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _tavilyCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: _tavilySaved ? '•••••••• saved' : 'tvly-…',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        final v = _tavilyCtrl.text.trim();
                        if (v.isEmpty) return;
                        await _store.setTavilyKey(v);
                        _tavilyCtrl.clear();
                        setState(() => _tavilySaved = true);
                      },
                      child: const Text('Save key'),
                    ),
                    const SizedBox(width: 10),
                    if (_tavilySaved)
                      TextButton(
                        onPressed: () async {
                          await _store.clearTavilyKey();
                          setState(() => _tavilySaved = false);
                        },
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Test connection',
            subtitle: 'Sends one tiny prompt to Groq with your saved key.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ElevatedButton(
                  onPressed: _groqSaved
                      ? () async {
                          setState(() => _testResult = 'Testing…');
                          try {
                            final key = await _store.groqKey;
                            final model = await _store.model;
                            final client = GroqClient(
                              apiKey: key!,
                              model: model,
                            );
                            final reply = await client.chat(
                              messages: [
                                {
                                  'role': 'user',
                                  'content': 'Reply with just the word OK.',
                                },
                              ],
                              maxTokens: 10,
                            );
                            setState(
                              () => _testResult = 'Works: $reply',
                            );
                          } catch (e) {
                            setState(() => _testResult = 'Failed: $e');
                          }
                        }
                      : null,
                  child: const Text('Test Groq'),
                ),
                if (_testResult != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_testResult!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Mascots: Bloub (MIT, by Jérémy Perret) — an SVG recreation of the x.ai/Grok bot avatar. The code is free to use, but the design resembles x.ai\'s — check before publishing the app commercially.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
