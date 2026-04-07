import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/supabase_config.dart';
import 'goat_setup_models.dart';

class GoatSetupInterpretOutcome {
  const GoatSetupInterpretOutcome({
    required this.interpretation,
    this.draftId,
    this.callsAfter,
    this.followupSuggested = false,
  });

  final GoatSetupInterpretResult interpretation;
  final String? draftId;
  final int? callsAfter;
  final bool followupSuggested;
}

/// Calls Edge `goat-setup-chat` (server-side Gemini). Max 2 calls per user enforced on server.
class GoatSetupInterpretService {
  GoatSetupInterpretService._();

  static bool get _isHostedWeb {
    if (!kIsWeb) return false;
    final h = Uri.base.host;
    return h != 'localhost' && h != '127.0.0.1' && h != '[::1]';
  }

  /// [callIndex] 1 = primary interpretation, 2 = follow-up merge (pass previous draft in context).
  static Future<GoatSetupInterpretOutcome> interpret({
    required String message,
    int callIndex = 1,
    Map<String, dynamic>? context,
  }) async {
    final client = Supabase.instance.client;
    final trimmed = message.trim();
    if (trimmed.length < 3) {
      throw ArgumentError('message_too_short');
    }

    final body = <String, dynamic>{
      'message': trimmed,
      'call_index': callIndex,
      if (context != null && context.isNotEmpty) 'context': context,
    };

    Map<String, dynamic> data;
    if (_isHostedWeb) {
      final session = client.auth.currentSession;
      if (session == null) throw StateError('Not signed in');
      final r = await http.post(
        Uri.parse('${Uri.base.origin}/api/goat-setup-chat'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode(body),
      );
      if (r.statusCode == 429) {
        throw StateError('ai_call_limit');
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('goat-setup-chat proxy ${r.statusCode} ${r.body}');
        }
        throw StateError('goat_setup_interpret_failed');
      }
      data = jsonDecode(r.body) as Map<String, dynamic>;
    } else {
      final res = await client.functions.invoke(
        'goat-setup-chat',
        body: body,
      );
      if (res.status == 429) {
        throw StateError('ai_call_limit');
      }
      if (res.data == null) {
        throw StateError('goat_setup_interpret_failed');
      }
      final raw = res.data is Map<String, dynamic>
          ? res.data as Map<String, dynamic>
          : jsonDecode(jsonEncode(res.data)) as Map<String, dynamic>;
      data = raw;
    }

    if (data['ok'] != true) {
      final err = data['error']?.toString() ?? 'unknown';
      throw StateError(err);
    }
    final interp = data['interpretation'];
    if (interp is! Map) {
      throw StateError('missing_interpretation');
    }
    final interpretation = GoatSetupInterpretResult.fromJson(Map<String, dynamic>.from(interp));
    final draftId = data['draft_id'] as String?;
    final callsAfter = data['calls_after'] is int ? data['calls_after'] as int : int.tryParse('${data['calls_after']}');
    final follow = data['followup_suggested'] == true;
    return GoatSetupInterpretOutcome(
      interpretation: interpretation,
      draftId: draftId,
      callsAfter: callsAfter,
      followupSuggested: follow,
    );
  }
}
