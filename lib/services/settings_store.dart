import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API keys and preferences. Keys live in secure storage only —
/// never hardcoded, never in plain text, never pasted in chat.
class SettingsStore {
  static const _storage = FlutterSecureStorage();

  static const _groqKey = 'groq_api_key';
  static const _tavilyKey = 'tavily_api_key';
  static const _modelKey = 'groq_model';

  /// Default chat model. Verify in the Groq console that the model is
  /// still on the free tier — Groq moves models between tiers.
  static const defaultModel = 'openai/gpt-oss-120b';

  Future<String?> get groqKey => _storage.read(key: _groqKey);
  Future<void> setGroqKey(String v) =>
      _storage.write(key: _groqKey, value: v.trim());
  Future<void> clearGroqKey() => _storage.delete(key: _groqKey);

  Future<String?> get tavilyKey => _storage.read(key: _tavilyKey);
  Future<void> setTavilyKey(String v) =>
      _storage.write(key: _tavilyKey, value: v.trim());
  Future<void> clearTavilyKey() => _storage.delete(key: _tavilyKey);

  Future<String> get model async =>
      (await _storage.read(key: _modelKey)) ?? defaultModel;
  Future<void> setModel(String v) =>
      _storage.write(key: _modelKey, value: v.trim());
}
