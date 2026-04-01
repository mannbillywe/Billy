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
    final uid = _uid;
    if (uid == null) return [];
    // Align with RLS: creator or linked counterparty can read the row.
    final res = await _client
        .from('lend_borrow_entries')
        .select(
          '*, creator_profile:profiles!lend_borrow_entries_user_id_fkey(display_name), '
          'counterparty_profile:profiles!lend_borrow_entries_counterparty_user_id_fkey(display_name)',
        )
        .or('user_id.eq.$uid,counterparty_user_id.eq.$uid')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> insertLendBorrow({
    required String counterpartyName,
    required double amount,
    required String type,
    String? notes,
    String? dueDate,
    String? counterpartyUserId,
    String? groupId,
  }) async {
    if (_uid == null) return;
    await _client.from('lend_borrow_entries').insert({
      'user_id': _uid,
      'counterparty_name': counterpartyName,
      'amount': amount,
      'type': type,
      'notes': notes,
      'due_date': dueDate,
      if (counterpartyUserId != null) 'counterparty_user_id': counterpartyUserId,
      if (groupId != null) 'group_id': groupId,
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

  static Future<void> updateProfile({
    String? displayName,
    String? avatarUrl,
    String? geminiApiKey,
    String? preferredCurrency,
  }) async {
    if (_uid == null) return;
    final updates = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (displayName != null) updates['display_name'] = displayName;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (geminiApiKey != null) updates['gemini_api_key'] = geminiApiKey;
    if (preferredCurrency != null) updates['preferred_currency'] = preferredCurrency;
    await _client.from('profiles').update(updates).eq('id', _uid!);
  }

  // ─── Social: invitations & connections ───────────────────────────
  static Future<void> syncInvitationRecipient() async {
    if (_uid == null) return;
    try {
      await _client.rpc('sync_invitation_recipient');
    } catch (_) {}
  }

  static Future<String?> inviteContactByEmail(String email) async {
    if (_uid == null) return null;
    final res = await _client.rpc('invite_contact_by_email', params: {'p_email': email.trim()});
    return res?.toString();
  }

  static Future<void> acceptContactInvitation(String invitationId) async {
    await _client.rpc('accept_contact_invitation', params: {'p_invitation_id': invitationId});
  }

  static Future<void> rejectContactInvitation(String invitationId) async {
    await _client.rpc('reject_contact_invitation', params: {'p_invitation_id': invitationId});
  }

  static Future<List<Map<String, dynamic>>> fetchContactInvitations() async {
    if (_uid == null) return [];
    final res = await _client.from('contact_invitations').select().order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<List<Map<String, dynamic>>> fetchUserConnections() async {
    final uid = _uid;
    if (uid == null) return [];
    final res = await _client
        .from('user_connections')
        .select()
        .or('user_low.eq.$uid,user_high.eq.$uid');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, dynamic>?> fetchProfileById(String userId) async {
    try {
      final res = await _client.from('profiles').select().eq('id', userId).maybeSingle();
      return res;
    } catch (_) {
      return null;
    }
  }

  // ─── Expense groups ──────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchExpenseGroups() async {
    if (_uid == null) return [];
    final res = await _client
        .from('expense_groups')
        .select(
          '*, expense_group_members('
          '*, member_profile:profiles!expense_group_members_user_id_fkey(display_name))',
        )
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Group ledger: expenses with shares and payer display name.
  static Future<List<Map<String, dynamic>>> fetchGroupExpenses(String groupId) async {
    if (_uid == null) return [];
    final res = await _client
        .from('group_expenses')
        .select(
          '*, payer:profiles!group_expenses_paid_by_user_id_fkey(display_name), '
          'group_expense_participants('
          '*, participant:profiles!group_expense_participants_user_id_fkey(display_name))',
        )
        .eq('group_id', groupId)
        .order('expense_date', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Atomic insert via [create_group_expense] RPC. [shares] entries:
  /// `{'user_id': uuid, 'share_amount': double}` — must sum to [amount].
  static Future<String> createGroupExpense({
    required String groupId,
    required String title,
    required double amount,
    required String paidByUserId,
    required DateTime expenseDate,
    required List<Map<String, dynamic>> shares,
  }) async {
    final res = await _client.rpc(
      'create_group_expense',
      params: {
        'p_group_id': groupId,
        'p_title': title,
        'p_amount': amount,
        'p_paid_by_user_id': paidByUserId,
        'p_expense_date': expenseDate.toIso8601String().split('T').first,
        'p_shares': shares,
      },
    );
    if (res == null) throw StateError('create_group_expense returned null');
    return res.toString();
  }

  static Future<void> deleteGroupExpense(String expenseId) async {
    await _client.from('group_expenses').delete().eq('id', expenseId);
  }

  static Future<Map<String, dynamic>> createExpenseGroup({required String name}) async {
    if (_uid == null) throw StateError('Not signed in');
    final row = await _client
        .from('expense_groups')
        .insert({'name': name, 'created_by': _uid})
        .select()
        .single();
    final gid = row['id'] as String;
    await _client.from('expense_group_members').insert({'group_id': gid, 'user_id': _uid, 'role': 'owner'});
    return Map<String, dynamic>.from(row);
  }

  static Future<void> addUserToExpenseGroup({required String groupId, required String memberUserId}) async {
    await _client.from('expense_group_members').insert({'group_id': groupId, 'user_id': memberUserId});
  }

  static Future<void> cancelOutgoingInvitation(String invitationId) async {
    await _client.from('contact_invitations').update({'status': 'cancelled'}).eq('id', invitationId);
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
