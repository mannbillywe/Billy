import 'package:flutter/foundation.dart';

/// Supabase URL and anon key.
///
/// **Mobile release:** pass `--dart-define-from-file=config/prod.json` (or per-define flags).
///
/// **Debug / Flutter web:** if defines are empty, uses embedded project URL + anon key so local run
/// and CI/Vercel builds without `config/prod.json` still boot. The anon key is public by design;
/// override with defines for a different Supabase project.
class SupabaseConfig {
  static const String _urlFromEnv = String.fromEnvironment('SUPABASE_URL');
  static const String _anonFromEnv = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const String _embeddedUrl = 'https://wpzopkigbbldcfpxuvcm.supabase.co';
  static const String _embeddedAnon =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indwem9wa2lnYmJsZGNmcHh1dmNtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4MTAxNzYsImV4cCI6MjA4OTM4NjE3Nn0.vps43fornSArjXvsiFQm4BSW6BuuXTMg_G11snC6OO8';

  static bool get _allowEmbeddedFallback => kDebugMode || kIsWeb;

  static String get url {
    if (_urlFromEnv.isNotEmpty) return _urlFromEnv;
    if (_allowEmbeddedFallback) {
      if (kIsWeb && !kDebugMode) {
        debugPrint(
          'SupabaseConfig: web release has no SUPABASE_URL define; using embedded default. '
          'Set Vercel env + dart-define for another project.',
        );
      } else if (kDebugMode) {
        debugPrint(
          'SupabaseConfig: SUPABASE_URL not set; using embedded default. '
          'Use --dart-define-from-file=config/dev.json to override.',
        );
      }
      return _embeddedUrl;
    }
    throw StateError(
      'Missing SUPABASE_URL. Build with: flutter build <target> --dart-define-from-file=config/prod.json',
    );
  }

  static String get anonKey {
    if (_anonFromEnv.isNotEmpty) return _anonFromEnv;
    if (_allowEmbeddedFallback) {
      return _embeddedAnon;
    }
    throw StateError(
      'Missing SUPABASE_ANON_KEY. Build with --dart-define-from-file=config/prod.json',
    );
  }
}
