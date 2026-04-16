import 'package:flutter/foundation.dart';

/// Base URL for the Billy AI Python backend (Cloud Run / FastAPI).
///
/// **Override:** `flutter run` / `flutter build` with:
/// `--dart-define=BILLY_AI_BACKEND_URL=https://your-other-host.example`
///
/// **Default:** Production Cloud Run URL when the define is omitted (safe to ship; not a secret).
class BillyAiBackendConfig {
  BillyAiBackendConfig._();

  static const String _fromEnv = String.fromEnvironment('BILLY_AI_BACKEND_URL');

  /// Production Billy AI backend (Google Cloud Run).
  static const String embeddedDefault = 'https://billy-ai-eq3uykqo2q-el.a.run.app';

  /// Resolved base URL with no trailing slash.
  static String get baseUrl {
    final raw = _fromEnv.trim().isNotEmpty ? _fromEnv.trim() : embeddedDefault;
    final normalized = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    if (kDebugMode && _fromEnv.trim().isEmpty) {
      debugPrint('BillyAiBackendConfig: using default backend $normalized');
    }
    return normalized;
  }

  /// `true` when a non-default URL was passed via `--dart-define`.
  static bool get usesCustomUrl => _fromEnv.trim().isNotEmpty;
}
