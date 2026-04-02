import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/supabase_config.dart';
import '../models/analytics_insights_models.dart';

/// Invokes `analytics-insights` (Supabase Edge or Vercel `/api` proxy on hosted web).
class AnalyticsInsightsService {
  AnalyticsInsightsService._();

  static bool get _hostedWeb =>
      kIsWeb &&
      Uri.base.hasScheme &&
      !Uri.base.host.contains('localhost') &&
      !Uri.base.host.startsWith('127.');

  static Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) {
      throw const FunctionException(status: 401, details: 'Not signed in');
    }

    if (_hostedWeb) {
      final url = Uri.parse('${Uri.base.origin}/api/analytics-insights');
      final r = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode(body),
      );
      final dynamic data;
      final ct = r.headers['content-type'] ?? '';
      if (ct.contains('application/json') && r.body.isNotEmpty) {
        data = jsonDecode(r.body) as Object?;
      } else {
        data = r.body;
      }
      if (r.statusCode >= 200 && r.statusCode < 300) {
        return Map<String, dynamic>.from(data as Map);
      }
      throw FunctionException(
        status: r.statusCode,
        details: data,
        reasonPhrase: r.reasonPhrase,
      );
    }

    final res = await client.functions.invoke(
      'analytics-insights',
      body: body,
    );
    if (res.status < 200 || res.status >= 300) {
      throw FunctionException(status: res.status, details: res.data);
    }
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    throw Exception('Invalid analytics response');
  }

  static Future<AnalyticsInsightsResult> refreshRange({
    required String rangePreset,
    bool includeAi = true,
  }) async {
    final raw = await _invoke({
      'range_preset': rangePreset,
      'include_ai': includeAi,
    });
    return AnalyticsInsightsResult.fromInvokeResponse(raw);
  }

  static Future<AnalyticsInsightsResult> reviewDocument({
    required String documentId,
    bool includeAi = true,
  }) async {
    final raw = await _invoke({
      'document_id': documentId,
      'include_ai': includeAi,
    });
    return AnalyticsInsightsResult.fromInvokeResponse(raw);
  }
}
