import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';

/// On-device history. One row per council run, newest first.
/// Local only — nothing leaves the phone.
class HistoryStore {
  static Database? _db;

  static Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'llm_council.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE runs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            question TEXT NOT NULL,
            answers TEXT NOT NULL,
            opinions TEXT NOT NULL,
            verdict TEXT NOT NULL,
            evidence TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<int> saveRun({
    required String question,
    required Map<String, String> answers,
    required List<Opinion> opinions,
    required Verdict verdict,
    required List<EvidenceSource> evidence,
  }) async {
    final db = await _database;
    return db.insert('runs', {
      'question': question,
      'answers': jsonEncode(answers),
      'opinions': jsonEncode(
        opinions
            .map((o) => {'advisorId': o.advisorId, 'text': o.text})
            .toList(),
      ),
      'verdict': jsonEncode(verdict.toJson()),
      'evidence': jsonEncode(evidence.map((e) => e.toJson()).toList()),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<List<SavedRun>> listRuns({int limit = 50}) async {
    final db = await _database;
    final rows = await db.query(
      'runs',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(SavedRun.fromRow).toList();
  }

  static Future<void> deleteRun(int id) async {
    final db = await _database;
    await db.delete('runs', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearAll() async {
    final db = await _database;
    await db.delete('runs');
  }
}

class SavedRun {
  SavedRun({
    required this.id,
    required this.question,
    required this.answers,
    required this.opinions,
    required this.verdict,
    required this.evidence,
    required this.createdAt,
  });

  final int id;
  final String question;
  final Map<String, String> answers;
  final List<Opinion> opinions;
  final Verdict verdict;
  final List<EvidenceSource> evidence;
  final DateTime createdAt;

  factory SavedRun.fromRow(Map<String, dynamic> row) {
    final answersJson =
        jsonDecode(row['answers'] as String) as Map<String, dynamic>;
    final opinionsJson = jsonDecode(row['opinions'] as String) as List;
    final evidenceJson = jsonDecode(row['evidence'] as String) as List;
    return SavedRun(
      id: row['id'] as int,
      question: row['question'] as String,
      answers: answersJson.map((k, v) => MapEntry(k, v.toString())),
      opinions: opinionsJson
          .map(
            (o) => Opinion(
              advisorId: (o as Map)['advisorId'].toString(),
              text: (o)['text'].toString(),
            ),
          )
          .toList(),
      verdict: Verdict.fromJson(
        jsonDecode(row['verdict'] as String) as Map<String, dynamic>,
      ),
      evidence: evidenceJson
          .map((e) => EvidenceSource.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }
}
