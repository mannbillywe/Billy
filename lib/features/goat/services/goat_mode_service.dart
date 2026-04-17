import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/supabase_config.dart';
import '../models/goat_models.dart';

/// Thrown by the service layer. The message is safe to surface to the user.
class GoatModeException implements Exception {
  final String message;
  final int? status;
  final Object? details;
  GoatModeException(this.message, {this.status, this.details});

  @override
  String toString() => 'GoatModeException($status): $message';
}

/// Thin presentation-focused Supabase binding for Goat Mode.
///
/// Responsibilities:
///   - invoke the `goat-mode-trigger` Edge Function (never Cloud Run directly)
///   - read Goat Mode tables (jobs / snapshots / recommendations) scoped by RLS
///
/// This class does NOT compute analytics. Any transformation happens on the
/// backend; Flutter only reads and renders.
class GoatModeService {
  GoatModeService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// When running on a hosted web origin (Vercel), calls go through the
  /// same-origin `/api/goat-mode-trigger` proxy — mirrors the analytics
  /// service pattern so CORS / auth behave identically.
  static bool get _hostedWeb =>
      kIsWeb &&
      Uri.base.hasScheme &&
      !Uri.base.host.contains('localhost') &&
      !Uri.base.host.startsWith('127.');

  // ──────────────────────────────────────────────────────────────────────
  // Trigger
  // ──────────────────────────────────────────────────────────────────────

  /// Ask the Supabase Edge Function to kick off a Goat Mode run.
  ///
  /// The Edge Function:
  ///   - validates auth + entitlement
  ///   - derives `user_id` from the JWT (we never send it from the client)
  ///   - forwards to the Cloud Run backend
  ///
  /// Returns the raw response map from the edge function (useful for
  /// dev/debug but the UI only needs the `job_id` if present).
  static Future<Map<String, dynamic>> triggerRefresh({
    GoatScope scope = GoatScope.full,
    DateTime? rangeStart,
    DateTime? rangeEnd,
    bool dryRun = false,
  }) async {
    final body = <String, dynamic>{
      'scope': scope.wire,
      if (rangeStart != null) 'range_start': _dateOnly(rangeStart),
      if (rangeEnd != null) 'range_end': _dateOnly(rangeEnd),
      if (dryRun) 'dry_run': true,
    };

    if (_hostedWeb) {
      final session = _client.auth.currentSession;
      if (session == null) {
        throw GoatModeException('Not signed in', status: 401);
      }
      final url = Uri.parse('${Uri.base.origin}/api/goat-mode-trigger');
      final r = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode(body),
      );
      final data = _decode(r.body, r.headers['content-type']);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        return data is Map ? Map<String, dynamic>.from(data) : const {};
      }
      throw GoatModeException(
        _pickMessage(data) ?? 'Goat Mode refresh failed (${r.statusCode})',
        status: r.statusCode,
        details: data,
      );
    }

    final res = await _client.functions.invoke('goat-mode-trigger', body: body);
    if (res.status < 200 || res.status >= 300) {
      throw GoatModeException(
        _pickMessage(res.data) ?? 'Goat Mode refresh failed (${res.status})',
        status: res.status,
        details: res.data,
      );
    }
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return const {};
  }

  // ──────────────────────────────────────────────────────────────────────
  // Reads (RLS-scoped to the signed-in user)
  // ──────────────────────────────────────────────────────────────────────

  /// Most recent job for this user (any scope).
  ///
  /// If [scope] is provided we filter to that scope; otherwise the newest
  /// row wins. We only need a tiny projection for polling.
  static Future<GoatJob?> fetchLatestJob({GoatScope? scope}) async {
    final q = _client
        .from('goat_mode_jobs')
        .select(
          'id,user_id,scope,status,readiness_level,error_message,started_at,finished_at,created_at',
        );
    final filtered = scope == null ? q : q.eq('scope', scope.wire);
    final rows = await filtered
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return GoatJob.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Single job by id — used by the polling loop so we don't keep selecting
  /// "latest" (which could race with a newer run triggered elsewhere).
  static Future<GoatJob?> fetchJobById(String jobId) async {
    final rows = await _client
        .from('goat_mode_jobs')
        .select(
          'id,user_id,scope,status,readiness_level,error_message,started_at,finished_at,created_at',
        )
        .eq('id', jobId)
        .limit(1);
    if (rows.isEmpty) return null;
    return GoatJob.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Most recent snapshot — defaults to the orchestration-wide `full` scope
  /// which always contains the merged overview + per-pillar metrics.
  static Future<GoatSnapshot?> fetchLatestSnapshot({
    GoatScope scope = GoatScope.full,
  }) async {
    final rows = await _client
        .from('goat_mode_snapshots')
        .select()
        .eq('scope', scope.wire)
        .order('generated_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return GoatSnapshot.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Open recommendations for the signed-in user, highest priority first.
  static Future<List<GoatRecommendation>> fetchOpenRecommendations({
    int limit = 20,
  }) async {
    final rows = await _client
        .from('goat_mode_recommendations')
        .select()
        .eq('status', 'open')
        .order('priority', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map((r) => GoatRecommendation.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }

  // ──────────────────────────────────────────────────────────────────────
  // helpers
  // ──────────────────────────────────────────────────────────────────────

  static String _dateOnly(DateTime d) {
    final u = d.toUtc();
    final m = u.month.toString().padLeft(2, '0');
    final day = u.day.toString().padLeft(2, '0');
    return '${u.year}-$m-$day';
  }

  static Object? _decode(String body, String? contentType) {
    if (body.isEmpty) return null;
    final ct = contentType ?? '';
    if (ct.contains('application/json')) {
      try {
        return jsonDecode(body);
      } catch (_) {
        return body;
      }
    }
    return body;
  }

  /// Best-effort extraction of a user-safe error message from edge / backend
  /// error payloads. Keeps things calm even when the upstream shape shifts.
  static String? _pickMessage(Object? d) {
    if (d is Map) {
      for (final k in const ['message', 'error', 'detail', 'code']) {
        final v = d[k];
        if (v is String && v.isNotEmpty) return v;
      }
    } else if (d is String && d.isNotEmpty) {
      return d;
    }
    return null;
  }
}
