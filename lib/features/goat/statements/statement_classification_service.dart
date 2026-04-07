import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/supabase_config.dart';

/// Optional pass-1 AI: classifies statement text excerpt (Edge Function → Gemini).
/// Failures are ignored; deterministic parsing remains authoritative.
class StatementClassificationService {
  StatementClassificationService._();

  /// Hosted production web: same-origin `/api/statement-classify` (Vercel) to avoid CORS.
  static bool get _isHostedWeb {
    if (!kIsWeb) return false;
    final h = Uri.base.host;
    return h != 'localhost' && h != '127.0.0.1' && h != '[::1]';
  }

  static Future<void> classifyImport({
    required String importId,
    required String textExcerpt,
  }) async {
    final trimmed = textExcerpt.trim();
    if (trimmed.isEmpty) return;
    final excerpt = trimmed.length > 8000 ? trimmed.substring(0, 8000) : trimmed;
    final client = Supabase.instance.client;
    try {
      if (_isHostedWeb) {
        final session = client.auth.currentSession;
        if (session == null) return;
        final r = await http.post(
          Uri.parse('${Uri.base.origin}/api/statement-classify'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
            'apikey': SupabaseConfig.anonKey,
          },
          body: jsonEncode({
            'import_id': importId,
            'text_excerpt': excerpt,
          }),
        );
        if ((r.statusCode < 200 || r.statusCode >= 300) && kDebugMode) {
          debugPrint('statement-classify proxy ${r.statusCode} ${r.body}');
        }
        return;
      }
      await client.functions.invoke(
        'statement-classify',
        body: {
          'import_id': importId,
          'text_excerpt': excerpt,
        },
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('statement-classify failed: $e\n$st');
      }
    }
  }
}
