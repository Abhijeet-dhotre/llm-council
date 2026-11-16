import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';
import '../services/history_store.dart';
import '../widgets/chat_bubbles.dart';

/// Past council runs, newest first. Tap one to reread it.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<SavedRun>> _runs;

  @override
  void initState() {
    super.initState();
    _runs = HistoryStore.listRuns();
  }

  String _date(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(
          'History',
          style: GoogleFonts.fraunces(fontWeight: FontWeight.w700),
        ),
        backgroundColor: const Color(0xFFF2F2F7),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear all',
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Clear all history?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (yes == true) {
                await HistoryStore.clearAll();
                setState(() => _runs = HistoryStore.listRuns());
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<SavedRun>>(
        future: _runs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final runs = snap.data ?? [];
          if (runs.isEmpty) {
            return Center(
              child: Text(
                'No council runs yet.\nAsk your first question.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.grey[600],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: runs.length,
            itemBuilder: (context, i) {
              final run = runs[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: Text(
                    run.question,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(_date(run.createdAt)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: run.verdict.decisionColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      run.verdict.decision.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _RunDetail(run: run),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// A saved run, read-only, in the same chat layout.
class _RunDetail extends StatelessWidget {
  const _RunDetail({required this.run});

  final SavedRun run;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(
          'Verdict',
          style: GoogleFonts.fraunces(fontWeight: FontWeight.w700),
        ),
        backgroundColor: const Color(0xFFF2F2F7),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          UserBubble(text: run.question),
          if (run.answers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 48),
              child: Text(
                run.answers.entries
                    .map((e) => 'Q: ${e.key}\nA: ${e.value}')
                    .join('\n\n'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
            ),
          for (final o in run.opinions)
            AdvisorBubble(
              advisor: Advisor.byId(o.advisorId),
              text: o.text,
            ),
          ChairmanBubble(verdict: run.verdict),
        ],
      ),
    );
  }
}
