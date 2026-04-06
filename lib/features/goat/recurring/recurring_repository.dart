import 'package:supabase_flutter/supabase_flutter.dart';

import 'recurring_cadence.dart';

class RecurringRepository {
  RecurringRepository._();

  static SupabaseClient get _c => Supabase.instance.client;
  static String? get _uid => _c.auth.currentUser?.id;

  static Future<List<Map<String, dynamic>>> fetchSeries() async {
    if (_uid == null) return [];
    final rows = await _c
        .from('recurring_series')
        .select()
        .eq('user_id', _uid!)
        .order('next_due_date', ascending: true);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<List<Map<String, dynamic>>> fetchOccurrences({
    DateTime? fromDue,
    DateTime? toDue,
    int limit = 100,
  }) async {
    if (_uid == null) return [];
    final fromStr = fromDue != null ? _ymd(fromDue) : null;
    final toStr = toDue != null ? _ymd(toDue) : null;

    final List<dynamic> rows;
    if (fromStr != null && toStr != null) {
      rows = await _c
          .from('recurring_occurrences')
          .select()
          .eq('user_id', _uid!)
          .gte('due_date', fromStr)
          .lte('due_date', toStr)
          .order('due_date', ascending: true)
          .limit(limit);
    } else if (fromStr != null) {
      rows = await _c
          .from('recurring_occurrences')
          .select()
          .eq('user_id', _uid!)
          .gte('due_date', fromStr)
          .order('due_date', ascending: true)
          .limit(limit);
    } else if (toStr != null) {
      rows = await _c
          .from('recurring_occurrences')
          .select()
          .eq('user_id', _uid!)
          .lte('due_date', toStr)
          .order('due_date', ascending: true)
          .limit(limit);
    } else {
      rows = await _c
          .from('recurring_occurrences')
          .select()
          .eq('user_id', _uid!)
          .order('due_date', ascending: true)
          .limit(limit);
    }
    return List<Map<String, dynamic>>.from(rows);
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Creates series + default in_app notification rule + [occurrenceCount] upcoming rows.
  static Future<String?> createManualSeries({
    required String title,
    required String kind,
    required String frequency,
    required DateTime nextDue,
    required double expectedAmount,
    String currency = 'INR',
    int intervalCount = 1,
    String? categoryId,
    bool autopay = false,
    String? autopayMethod,
    int reminderDaysBefore = 3,
    int occurrenceCount = 4,
  }) async {
    final uid = _uid;
    if (uid == null) return null;

    final row = {
      'user_id': uid,
      'kind': kind,
      'source': 'manual',
      'status': 'active',
      'title': title,
      'frequency': frequency,
      'interval_count': intervalCount,
      'next_due_date': _ymd(nextDue),
      'expected_amount': expectedAmount,
      'currency': currency,
      'autopay_enabled': autopay,
      if (autopayMethod != null) 'autopay_method': autopayMethod,
      'reminder_days_before': reminderDaysBefore,
      if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
      'metadata': <String, dynamic>{},
    };

    final inserted = await _c.from('recurring_series').insert(row).select('id').single();
    final seriesId = inserted['id'] as String?;

    if (seriesId == null) return null;

    await _c.from('recurring_notification_rules').insert({
      'user_id': uid,
      'series_id': seriesId,
      'channel': 'in_app',
      'days_before': reminderDaysBefore,
      'enabled': true,
    });

    await generateOccurrencesForSeries(
      seriesId: seriesId,
      userId: uid,
      startDue: nextDue,
      frequency: frequency,
      intervalCount: intervalCount,
      expectedAmount: expectedAmount,
      count: occurrenceCount,
    );

    return seriesId;
  }

  static Future<void> generateOccurrencesForSeries({
    required String seriesId,
    required String userId,
    required DateTime startDue,
    required String frequency,
    required int intervalCount,
    required double expectedAmount,
    int count = 4,
  }) async {
    var d = DateTime(startDue.year, startDue.month, startDue.day);
    for (var i = 0; i < count; i++) {
      await _c.from('recurring_occurrences').insert({
        'series_id': seriesId,
        'user_id': userId,
        'due_date': _ymd(d),
        'expected_amount': expectedAmount,
        'status': 'upcoming',
        'detection_source': 'manual',
      });
      d = addRecurringPeriod(d, frequency, intervalCount);
    }
  }

  static Future<void> pauseSeries(String seriesId) async {
    if (_uid == null) return;
    await _c.from('recurring_series').update({'status': 'paused'}).eq('id', seriesId).eq('user_id', _uid!);
  }

  static Future<void> resumeSeries(String seriesId) async {
    if (_uid == null) return;
    await _c.from('recurring_series').update({'status': 'active'}).eq('id', seriesId).eq('user_id', _uid!);
  }
}
