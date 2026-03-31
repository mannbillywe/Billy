import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  // ─── Documents ───────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchDocuments() async {
    if (_uid == null) return [];
    final res = await _client
        .from('documents')
        .select()
        .eq('user_id', _uid!)
        .order('date', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> insertDocument({
    required String vendorName,
    required double amount,
    required double taxAmount,
    required String date,
    String type = 'receipt',
    String? category,
    String? paymentMethod,
    String? description,
    Map<String, dynamic>? extractedData,
  }) async {
    if (_uid == null) return;
    await _client.from('documents').insert({
      'user_id': _uid,
      'vendor_name': vendorName,
      'amount': amount,
      'tax_amount': taxAmount,
      'date': date,
      'type': type,
      'description': description,
      'payment_method': paymentMethod,
      'extracted_data': extractedData,
      'status': 'saved',
    });
  }

  static Future<void> deleteDocument(String id) async {
    await _client.from('documents').delete().eq('id', id);
  }

  // ─── Lend / Borrow ──────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchLendBorrow() async {
    if (_uid == null) return [];
    final res = await _client
        .from('lend_borrow_entries')
        .select()
        .eq('user_id', _uid!)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> insertLendBorrow({
    required String counterpartyName,
    required double amount,
    required String type,
    String? notes,
    String? dueDate,
  }) async {
    if (_uid == null) return;
    await _client.from('lend_borrow_entries').insert({
      'user_id': _uid,
      'counterparty_name': counterpartyName,
      'amount': amount,
      'type': type,
      'notes': notes,
      'due_date': dueDate,
    });
  }

  static Future<void> settleLendBorrow(String id) async {
    await _client
        .from('lend_borrow_entries')
        .update({'status': 'settled', 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }

  static Future<void> deleteLendBorrow(String id) async {
    await _client.from('lend_borrow_entries').delete().eq('id', id);
  }

  // ─── Splits ──────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchSplits() async {
    if (_uid == null) return [];
    final res = await _client
        .from('splits')
        .select('*, split_participants(*)')
        .eq('user_id', _uid!)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> insertSplit({
    required String title,
    required double totalAmount,
    required List<Map<String, dynamic>> participants,
  }) async {
    if (_uid == null) return;
    final splitRes = await _client.from('splits').insert({
      'user_id': _uid,
      'title': title,
      'total_amount': totalAmount,
    }).select().single();

    final splitId = splitRes['id'];
    for (final p in participants) {
      await _client.from('split_participants').insert({
        'split_id': splitId,
        'name': p['name'],
        'amount_owed': p['amount_owed'],
      });
    }
  }

  // ─── Profile ─────────────────────────────────────────────────────
  /// Returns the current user's Gemini API key if set. Null = use app default.
  static Future<String?> getGeminiApiKey() async {
    if (_uid == null) return null;
    try {
      final res = await _client
          .from('profiles')
          .select('gemini_api_key')
          .eq('id', _uid!)
          .maybeSingle();
      final key = res?['gemini_api_key'] as String?;
      return (key != null && key.trim().isNotEmpty) ? key.trim() : null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> fetchProfile() async {
    if (_uid == null) return null;
    try {
      final res = await _client
          .from('profiles')
          .select()
          .eq('id', _uid!)
          .single();
      return res;
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateProfile({String? displayName, String? avatarUrl, String? geminiApiKey}) async {
    if (_uid == null) return;
    final updates = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (displayName != null) updates['display_name'] = displayName;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (geminiApiKey != null) updates['gemini_api_key'] = geminiApiKey;
    await _client.from('profiles').update(updates).eq('id', _uid!);
  }

  // ─── Connected Apps ──────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchConnectedApps() async {
    if (_uid == null) return [];
    final res = await _client
        .from('connected_apps')
        .select()
        .eq('user_id', _uid!)
        .order('app_name');
    return List<Map<String, dynamic>>.from(res);
  }

  // ─── Dashboard aggregations ──────────────────────────────────────
  static Future<double> todaySpend() async {
    if (_uid == null) return 0;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final res = await _client
        .from('documents')
        .select('amount')
        .eq('user_id', _uid!)
        .eq('date', today);
    double total = 0;
    for (final row in res) {
      total += (row['amount'] as num).toDouble();
    }
    return total;
  }

  static Future<double> weekSpend({required DateTime weekStart, required DateTime weekEnd}) async {
    if (_uid == null) return 0;
    final res = await _client
        .from('documents')
        .select('amount')
        .eq('user_id', _uid!)
        .gte('date', weekStart.toIso8601String().substring(0, 10))
        .lte('date', weekEnd.toIso8601String().substring(0, 10));
    double total = 0;
    for (final row in res) {
      total += (row['amount'] as num).toDouble();
    }
    return total;
  }

  static Future<List<Map<String, dynamic>>> recentDocuments({int limit = 10}) async {
    if (_uid == null) return [];
    final res = await _client
        .from('documents')
        .select()
        .eq('user_id', _uid!)
        .order('date', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, double>> categoryBreakdown() async {
    if (_uid == null) return {};
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final res = await _client
        .from('documents')
        .select('amount, description')
        .eq('user_id', _uid!)
        .gte('date', weekAgo.toIso8601String().substring(0, 10));
    final map = <String, double>{};
    for (final row in res) {
      final cat = (row['description'] as String?) ?? 'Other';
      map[cat] = (map[cat] ?? 0) + (row['amount'] as num).toDouble();
    }
    return map;
  }

  static Future<List<double>> dailySpendForWeek() async {
    if (_uid == null) return List.filled(7, 0);
    final now = DateTime.now();
    final result = <double>[];
    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final dayStr = day.toIso8601String().substring(0, 10);
      final res = await _client
          .from('documents')
          .select('amount')
          .eq('user_id', _uid!)
          .eq('date', dayStr);
      double total = 0;
      for (final row in res) {
        total += (row['amount'] as num).toDouble();
      }
      result.add(total);
    }
    return result;
  }
}
