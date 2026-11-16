import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Minimal OpenAI-compatible chat client pointed at Groq.
/// One model, five advisors — the council is five personas on the
/// same model, not five different models.
class GroqClient {
  GroqClient({required this.apiKey, required this.model});

  final String apiKey;
  final String model;

  static const _base = 'https://api.groq.com/openai/v1';

  /// Single chat completion. Returns the assistant text.
  /// Throws [GroqException] on HTTP or API errors.
  ///
  /// A 429 (rate limit) is retried automatically: Groq's free tier
  /// caps gpt-oss-120b at 8,000 tokens/minute, and the council fires
  /// five advisor calls in parallel, so a burst can trip it. Groq
  /// tells us how long to wait — the retry-after header, or
  /// "try again in Xs" in the error body — so we wait that long
  /// (plus a second) and try again, up to 4 attempts total.
  Future<String> chat({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 1200,
    bool jsonMode = false,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
    };
    if (jsonMode) {
      body['response_format'] = {'type': 'json_object'};
    }
    const maxAttempts = 4;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final res = await http
          .post(
            Uri.parse('$_base/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          throw const GroqException('Groq returned no answer.');
        }
        final content =
            (choices.first as Map<String, dynamic>)['message']?['content'];
        if (content is! String || content.trim().isEmpty) {
          throw const GroqException('Groq returned an empty answer.');
        }
        return content;
      }
      if (res.statusCode == 429 && attempt < maxAttempts) {
        await Future.delayed(_retryDelay(res));
        continue;
      }
      throw GroqException(_readError(res));
    }
    throw const GroqException(
      'Groq is still rate-limited after a few retries. '
      'Please wait a minute and try again.',
    );
  }

  /// How long to wait before retrying a 429. Prefers Groq's
  /// retry-after header (seconds), then the "try again in Xs"
  /// in the error body, then a growing fallback.
  static Duration _retryDelay(http.Response res) {
    final header = res.headers['retry-after'];
    final fromHeader = double.tryParse(header ?? '');
    if (fromHeader != null && fromHeader > 0) {
      return Duration(milliseconds: (fromHeader * 1000).round() + 1000);
    }
    final msg = _readError(res);
    final match = RegExp(r'try again in ([\d.]+)s').firstMatch(msg);
    final fromBody = match == null ? null : double.tryParse(match.group(1)!);
    if (fromBody != null && fromBody > 0) {
      return Duration(milliseconds: (fromBody * 1000).round() + 1000);
    }
    return const Duration(seconds: 10);
  }

  /// Same as [chat], but parses the reply as JSON. If the model
  /// wraps the JSON in code fences or extra text, the JSON block
  /// is extracted first.
  Future<Map<String, dynamic>> chatJson({
    required List<Map<String, String>> messages,
    double temperature = 0.5,
    int maxTokens = 1200,
  }) async {
    final raw = await chat(
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      jsonMode: true,
    );
    return _extractJson(raw);
  }

  static Map<String, dynamic> _extractJson(String raw) {
    final trimmed = raw.trim();
    try {
      final direct = jsonDecode(trimmed);
      if (direct is Map<String, dynamic>) return direct;
    } catch (_) {}
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final decoded = jsonDecode(trimmed.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) return decoded;
    }
    throw GroqException('Could not read the reply as JSON: $trimmed');
  }

  static String _readError(http.Response res) {
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final msg = data['error']?['message']?.toString();
      if (msg != null && msg.isNotEmpty) return 'Groq ${res.statusCode}: $msg';
    } catch (_) {}
    return 'Groq ${res.statusCode}: ${res.body}';
  }
}

class GroqException implements Exception {
  const GroqException(this.message);
  final String message;
  @override
  String toString() => message;
}
