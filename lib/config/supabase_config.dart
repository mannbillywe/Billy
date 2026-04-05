import 'package:flutter/foundation.dart';

/// Supabase URL and anon key.
///
/// **Production / release:** pass at build time so secrets are not the only source of truth:
/// `flutter build apk --dart-define-from-file=config/prod.json`
///
/// **Debug:** if defines are empty, falls back to the project defaults below so `flutter run` works.
class SupabaseConfig {
  static const String _urlFromEnv = String.fromEnvironment('SUPABASE_URL');
  static const String _anonFromEnv = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Debug-only fallbacks (replace via dart-define for staging/prod).
  static const String _debugFallbackUrl = 'https://wpzopkigbbldcfpxuvcm.supabase.co';
  static const String _debugFallbackAnon =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indwem9wa2lnYmJsZGNmcHh1dmNtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4MTAxNzYsImV4cCI6MjA4OTM4NjE3Nn0.vps43fornSArjXvsiFQm4BSW6BuuXTMg_G11snC6OO8';

  static String get url {
    if (_urlFromEnv.isNotEmpty) return _urlFromEnv;
    if (kDebugMode) {
      debugPrint(
        'SupabaseConfig: SUPABASE_URL not set; using debug fallback. '
        'Use --dart-define-from-file=config/dev.json for explicit config.',
      );
      return _debugFallbackUrl;
    }
    throw StateError(
      'Missing SUPABASE_URL. Build with: flutter build <target> --dart-define-from-file=config/prod.json',
    );
  }

  static String get anonKey {
    if (_anonFromEnv.isNotEmpty) return _anonFromEnv;
    if (kDebugMode) {
      return _debugFallbackAnon;
    }
    throw StateError(
      'Missing SUPABASE_ANON_KEY. Build with --dart-define-from-file=config/prod.json',
    );
  }
}
