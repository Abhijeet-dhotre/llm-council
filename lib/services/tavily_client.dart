import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Optional live facts. Tavily gives clean, LLM-ready search results:
/// 1,000 free credits a month, no card. If no key is set, the council
/// simply runs without live facts and says so in the verdict.
class TavilyClient {
  TavilyClient({required this.apiKey});

  final String apiKey;

  Future<List<EvidenceSource>> search(
    String query, {
    int maxResults = 5,
  }) async {
    final res = await http
        .post(
          Uri.parse('https://api.tavily.com/search'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'api_key': apiKey,
            'query': query,
            'max_results': maxResults,
            'search_depth': 'basic',
            'include_answer': false,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw TavilyException('Tavily ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final results = data['results'] as List? ?? [];
    return results.map((r) {
      final m = r as Map<String, dynamic>;
      return EvidenceSource(
        title: (m['title'] ?? '').toString(),
        url: (m['url'] ?? '').toString(),
        snippet: (m['content'] ?? '').toString(),
        date: (m['published_date'] ?? '').toString(),
      );
    }).toList();
  }
}

class TavilyException implements Exception {
  TavilyException(this.message);
  final String message;
  @override
  String toString() => message;
}
