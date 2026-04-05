import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/documents/models/document_category_source.dart';
import '../features/scanner/models/extracted_receipt.dart';

class SupabaseService {
  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  /// Remote DB may not have applied `documents.category_source` migration yet (PGRST204).
  static bool _isMissingCategorySourceColumnError(Object e) {
    final s = e.toString();
    return s.contains('PGRST204') && s.contains('category_source');
  }

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

  /// Paged fetch for large histories ([offset] is 0-based row index in sort order).
  static Future<List<Map<String, dynamic>>> fetchDocumentsPaged({
    required int limit,
    required int offset,
  }) async {
    if (_uid == null) return [];
    if (limit <= 0) return [];
    final from = offset;
    final to = offset + limit - 1;
    final res = await _client
        .from('documents')
        .select()
        .eq('user_id', _uid!)
        .order('date', ascending: false)
        .range(from, to);
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
    String? currency,
    Map<String, dynamic>? extractedData,
    String status = 'saved',
    String? categoryId,
    String? categorySource,
  }) async {
    if (_uid == null) return;
    final row = <String, dynamic>{
      'user_id': _uid,
      'vendor_name': vendorName,
      'amount': amount,
      'tax_amount': taxAmount,
      'date': date,
      'type': type,
      'description': description,
      'payment_method': paymentMethod,
      if (currency != null && currency.isNotEmpty) 'currency': currency,
      'extracted_data': extractedData,
      'status': status,
      if (categoryId != null) 'category_id': categoryId,
      if (categorySource != null) 'category_source': categorySource,
    };
    try {
      await _client.from('documents').insert(row);
    } catch (e) {
      if (categorySource != null && _isMissingCategorySourceColumnError(e)) {
        row.remove('category_source');
        await _client.from('documents').insert(row);
        return;
      }
      rethrow;
    }
  }

  static Future<void> deleteDocument(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('documents').delete().eq('id', id).eq('user_id', uid);
  }

  /// Single document for detail / edit flows.
  static Future<Map<String, dynamic>?> fetchDocumentById(String id) async {
    final uid = _uid;
    if (uid == null) return null;
    final res = await _client
        .from('documents')
        .select()
        .eq('id', id)
        .eq('user_id', uid)
        .maybeSingle();
    return res;
  }

  static Future<void> updateDocument({
    required String id,
    String? vendorName,
    double? amount,
    double? taxAmount,
    String? date,
    String? type,
    String? description,
    String? paymentMethod,
    String? currency,
    Map<String, dynamic>? extractedData,
    String? status,
    String? categoryId,
    String? categorySource,
    bool writeCategorySource = false,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (vendorName != null) updates['vendor_name'] = vendorName;
    if (amount != null) updates['amount'] = amount;
    if (taxAmount != null) updates['tax_amount'] = taxAmount;
    if (date != null) updates['date'] = date;
    if (type != null) updates['type'] = type;
    if (description != null) updates['description'] = description;
    if (paymentMethod != null) updates['payment_method'] = paymentMethod;
    if (currency != null && currency.isNotEmpty) updates['currency'] = currency;
    if (extractedData != null) updates['extracted_data'] = extractedData;
    if (status != null) updates['status'] = status;
    if (categoryId != null) updates['category_id'] = categoryId;
    if (writeCategorySource) {
      updates['category_source'] = categorySource;
    }
    try {
      await _client.from('documents').update(updates).eq('id', id).eq('user_id', uid);
    } catch (e) {
      if (writeCategorySource &&
          updates.containsKey('category_source') &&
          _isMissingCategorySourceColumnError(e)) {
        updates.remove('category_source');
        await _client.from('documents').update(updates).eq('id', id).eq('user_id', uid);
        return;
      }
      rethrow;
    }
  }

  /// Match `categories.name` for default (`user_id` null) or current user rows.
  static Future<String?> resolveCategoryIdByName(String name) async {
    final uid = _uid;
    if (uid == null || name.trim().isEmpty) return null;
    final n = name.trim().toLowerCase();
    final res = await _client
        .from('categories')
        .select('id,name,user_id')
        .or('user_id.is.null,user_id.eq.$uid');
    final list = List<Map<String, dynamic>>.from(res as List);
    for (final row in list) {
      final nm = (row['name'] as String?)?.toLowerCase();
      if (nm == n) return row['id'] as String?;
    }
    return null;
  }

  /// After OCR re-runs on linked invoice, refresh the `documents` row from `invoices` + `invoice_items`.
  static Future<void> syncDocumentFromLinkedInvoice(String documentId) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final doc = await fetchDocumentById(documentId);
    if (doc == null) return;
    final prev = doc['extracted_data'];
    final prevMap = prev is Map ? Map<String, dynamic>.from(prev) : <String, dynamic>{};
    final invoiceId = prevMap['invoice_id']?.toString();
    if (invoiceId == null || invoiceId.isEmpty) return;

    final inv = await _client.from('invoices').select().eq('id', invoiceId).eq('user_id', uid).maybeSingle();
    if (inv == null) return;
    final itemsRes = await _client.from('invoice_items').select().eq('invoice_id', invoiceId);
    final itemsList = (itemsRes as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];

    final receipt = ExtractedReceipt.fromInvoiceOcr(
      Map<String, dynamic>.from(inv as Map),
      itemsList,
    );
    final newEd = Map<String, dynamic>.from(receipt.toJson());
    const preserveKeys = <String>[
      'line_selection',
      'allocation_total',
      'intent_group_expense',
      'group_id',
      'intent_lend_borrow',
      'lend_type',
      'lend_counterparty',
      'invoice_id',
      'user_flagged_mismatch',
      'source',
    ];
    for (final k in preserveKeys) {
      if (prevMap[k] != null) newEd[k] = prevMap[k];
    }
    newEd['invoice_id'] = invoiceId;

    final taxStored = receipt.cgst + receipt.sgst + receipt.igst > 0
        ? receipt.cgst + receipt.sgst + receipt.igst
        : receipt.tax;
    final descParts = <String>{};
    if (receipt.category != null && receipt.category!.trim().isNotEmpty) {
      descParts.add(receipt.category!);
    }
    for (final li in receipt.lineItems) {
      if (li.category != null && li.category!.trim().isNotEmpty) descParts.add(li.category!);
    }

    final catId = descParts.isNotEmpty ? await resolveCategoryIdByName(descParts.first) : null;

    await updateDocument(
      id: documentId,
      vendorName: receipt.vendorName,
      amount: receipt.total,
      taxAmount: taxStored,
      date: receipt.date.isNotEmpty ? receipt.date : doc['date'] as String? ?? '',
      type: (receipt.invoiceNumber != null && receipt.invoiceNumber!.trim().isNotEmpty) ? 'invoice' : 'receipt',
      description: descParts.isEmpty ? null : descParts.join(', '),
      currency: receipt.currency,
      categoryId: catId,
      categorySource: catId != null ? DocumentCategorySource.rule : null,
      writeCategorySource: true,
      extractedData: newEd,
    );
  }

  static Future<void> insertExportHistory({
    required String format,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('export_history').insert({
      'user_id': uid,
      'format': format,
      'date_range_start': rangeStart.toIso8601String().substring(0, 10),
      'date_range_end': rangeEnd.toIso8601String().substring(0, 10),
    });
  }

  static Future<List<Map<String, dynamic>>> fetchExportHistory({int limit = 100}) async {
    final uid = _uid;
    if (uid == null) return [];
    final res = await _client
        .from('export_history')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Last saved analytics snapshot for [rangePreset] (`1W` | `1M` | `3M`). Read-only cache row.
  static Future<Map<String, dynamic>?> fetchAnalyticsInsightSnapshot(String rangePreset) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final res = await _client
          .from('analytics_insight_snapshots')
          .select()
          .eq('user_id', uid)
          .eq('range_preset', rangePreset)
          .maybeSingle();
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Signed URL to open original scan in Storage (invoice OCR pipeline).
  static Future<String?> signedUrlForInvoiceFile(String filePath, {int seconds = 3600}) async {
    if (_uid == null) return null;
    try {
      return await _client.storage.from('invoice-files').createSignedUrl(filePath, seconds);
    } catch (_) {
      return null;
    }
  }

  /// Header row for linked OCR invoice (file_path, mime_type, etc.).
  static Future<Map<String, dynamic>?> fetchInvoiceHeaderForUser(String invoiceId) async {
    final uid = _uid;
    if (uid == null) return null;
    final res = await _client
        .from('invoices')
        .select('id,file_path,mime_type,status,vendor_name,review_required')
        .eq('id', invoiceId)
        .eq('user_id', uid)
        .maybeSingle();
    return res;
  }

  // ─── Invoices (OCR pipeline) ───────────────────────────────────
  /// Persists user edits after review; sets status `confirmed` and replaces line items.
  static Future<void> syncInvoiceAfterReview({
    required String invoiceId,
    required Map<String, dynamic> header,
    required List<Map<String, dynamic>> itemRows,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    await _client.from('invoice_items').delete().eq('invoice_id', invoiceId);
    if (itemRows.isNotEmpty) {
      await _client.from('invoice_items').insert(itemRows);
    }
    await _client.from('invoices').update({
      ...header,
      'status': 'confirmed',
      'review_required': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', invoiceId).eq('user_id', uid);
  }

  // ─── Lend / Borrow ──────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchLendBorrow() async {
    final uid = _uid;
    if (uid == null) return [];
    // Align with RLS: creator or linked counterparty can read the row.
    try {
      final res = await _client
          .from('lend_borrow_entries')
          .select(
            '*, creator_profile:profiles!lend_borrow_entries_user_id_fkey(display_name), '
            'counterparty_profile:profiles!lend_borrow_entries_counterparty_user_id_fkey(display_name)',
          )
          .or('user_id.eq.$uid,counterparty_user_id.eq.$uid')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      // FK hint names can differ on some projects; still return rows for UI.
      final res = await _client
          .from('lend_borrow_entries')
          .select()
          .or('user_id.eq.$uid,counterparty_user_id.eq.$uid')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    }
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
    if (_uid == null) throw StateError('Not signed in');
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
    String? preferredCurrency,
  }) async {
    if (_uid == null) return;
    final updates = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (displayName != null) updates['display_name'] = displayName;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
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

  /// Batch profile lookup (avoids N+1 in connections UI).
  static Future<List<Map<String, dynamic>>> fetchProfilesByIds(List<String> userIds) async {
    final unique = userIds.toSet().toList();
    if (unique.isEmpty) return [];
    try {
      final res = await _client
          .from('profiles')
          .select('id, display_name, avatar_url')
          .inFilter('id', unique);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (_) {
      return [];
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

  static Future<List<Map<String, dynamic>>> fetchGroupSettlements(String groupId) async {
    if (_uid == null) return [];
    final res = await _client
        .from('group_settlements')
        .select(
          '*, payer_profile:profiles!group_settlements_payer_user_id_fkey(display_name), '
          'payee_profile:profiles!group_settlements_payee_user_id_fkey(display_name)',
        )
        .eq('group_id', groupId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> insertGroupSettlement({
    required String groupId,
    required String payeeUserId,
    required double amount,
    String? note,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    await _client.from('group_settlements').insert({
      'group_id': groupId,
      'payer_user_id': uid,
      'payee_user_id': payeeUserId,
      'amount': amount,
      if (note != null && note.isNotEmpty) 'note': note,
      'created_by': uid,
    });
  }

  static Future<void> deleteGroupSettlement(String settlementId) async {
    await _client.from('group_settlements').delete().eq('id', settlementId);
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

  // ─── Usage Limits ────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> fetchUsageLimits() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final res = await _client.rpc('maybe_reset_usage', params: {'p_user_id': uid});
      if (res is Map) return Map<String, dynamic>.from(res);
      if (res is List && res.isNotEmpty) return Map<String, dynamic>.from(res.first as Map);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Increment OCR scan counter. Throws if limit reached.
  static Future<Map<String, dynamic>> incrementOcrScan() async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final res = await _client.rpc('increment_ocr_scan', params: {'p_user_id': uid});
    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty) return Map<String, dynamic>.from(res.first as Map);
    throw StateError('Failed to increment OCR scan counter');
  }

  /// Increment refresh counter. Throws if limit reached.
  static Future<Map<String, dynamic>> incrementRefreshCount() async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final res = await _client.rpc('increment_refresh_count', params: {'p_user_id': uid});
    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty) return Map<String, dynamic>.from(res.first as Map);
    throw StateError('Failed to increment refresh counter');
  }

  /// Check if OCR scans are available without incrementing.
  static Future<bool> canPerformOcrScan() async {
    final usage = await fetchUsageLimits();
    if (usage == null) return true;
    final used = (usage['ocr_scans_used'] as num?)?.toInt() ?? 0;
    final limit = (usage['ocr_scans_limit'] as num?)?.toInt() ?? 5;
    return used < limit;
  }

  /// Check if refreshes are available without incrementing.
  static Future<bool> canPerformRefresh() async {
    final usage = await fetchUsageLimits();
    if (usage == null) return true;
    final used = (usage['refresh_used'] as num?)?.toInt() ?? 0;
    final limit = (usage['refresh_limit'] as num?)?.toInt() ?? 5;
    return used < limit;
  }

  // ─── Dashboard aggregations ──────────────────────────────────────
  static Future<double> todaySpend() async {
    if (_uid == null) return 0;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final res = await _client
        .from('documents')
        .select('amount')
        .eq('user_id', _uid!)
        .eq('date', today)
        .neq('status', 'draft');
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
        .lte('date', weekEnd.toIso8601String().substring(0, 10))
        .neq('status', 'draft');
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
        .neq('status', 'draft')
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
        .gte('date', weekAgo.toIso8601String().substring(0, 10))
        .neq('status', 'draft');
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
    final start = now.subtract(const Duration(days: 6));
    final startStr = start.toIso8601String().substring(0, 10);
    final endStr = now.toIso8601String().substring(0, 10);
    final res = await _client
        .from('documents')
        .select('date, amount')
        .eq('user_id', _uid!)
        .gte('date', startStr)
        .lte('date', endStr)
        .neq('status', 'draft');
    final byDay = <String, double>{};
    for (final row in res) {
      final d = row['date'] as String?;
      if (d == null) continue;
      final a = (row['amount'] as num?)?.toDouble() ?? 0;
      byDay[d] = (byDay[d] ?? 0) + a;
    }
    final result = <double>[];
    for (int i = 6; i >= 0; i--) {
      final dayStr = now.subtract(Duration(days: i)).toIso8601String().substring(0, 10);
      result.add(byDay[dayStr] ?? 0);
    }
    return result;
  }
}
