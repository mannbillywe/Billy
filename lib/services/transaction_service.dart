import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity_logger.dart';
import 'allocation_service.dart';

class TransactionService {
  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  static Future<String?> insertTransaction({
    required double amount,
    required String date,
    required String type,
    required String title,
    required String sourceType,
    String? description,
    String? categoryId,
    String? categorySource,
    String? paymentMethod,
    String? currency,
    String? sourceDocumentId,
    String? sourceImportId,
    double? effectiveAmount,
    String? groupId,
    String? groupExpenseId,
    String? lendBorrowId,
    String? settlementId,
    String status = 'confirmed',
    bool isRecurring = false,
    String? recurringSeriesId,
    String? notes,
    List<String>? tags,
    Map<String, dynamic>? extractedData,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    final row = <String, dynamic>{
      'user_id': uid,
      'amount': amount,
      'currency': currency ?? 'INR',
      'date': date,
      'type': type,
      'title': title,
      'source_type': sourceType,
      'status': status,
      'is_recurring': isRecurring,
      if (description != null) 'description': description,
      if (categoryId != null) 'category_id': categoryId,
      if (categorySource != null) 'category_source': categorySource,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (sourceDocumentId != null) 'source_document_id': sourceDocumentId,
      if (sourceImportId != null) 'source_import_id': sourceImportId,
      'effective_amount': effectiveAmount ?? amount,
      if (groupId != null) 'group_id': groupId,
      if (groupExpenseId != null) 'group_expense_id': groupExpenseId,
      if (lendBorrowId != null) 'lend_borrow_id': lendBorrowId,
      if (settlementId != null) 'settlement_id': settlementId,
      if (recurringSeriesId != null) 'recurring_series_id': recurringSeriesId,
      if (notes != null) 'notes': notes,
      if (tags != null) 'tags': tags,
      if (extractedData != null) 'extracted_data': extractedData,
    };
    final res = await _client.from('transactions').insert(row).select('id').single();
    final txnId = res['id'] as String?;

    await ActivityLogger.log(
      eventType: 'transaction_created',
      summary: '$type: $title — ${currency ?? "INR"} $amount',
      transactionId: txnId,
      groupId: groupId,
      entityType: 'transaction',
      entityId: txnId,
      visibility: groupId != null ? 'group' : 'private',
    );

    return txnId;
  }

  static Future<List<Map<String, dynamic>>> fetchTransactions({
    int limit = 50,
    int offset = 0,
    String? type,
    String? status,
    String? groupId,
  }) async {
    final uid = _uid;
    if (uid == null) return [];
    var query = _client.from('transactions').select().eq('user_id', uid);
    if (type != null) query = query.eq('type', type);
    if (status != null) query = query.eq('status', status);
    if (groupId != null) query = query.eq('group_id', groupId);
    final res = await query
        .order('date', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, dynamic>?> fetchTransactionById(String id) async {
    final uid = _uid;
    if (uid == null) return null;
    return await _client
        .from('transactions')
        .select()
        .eq('id', id)
        .eq('user_id', uid)
        .maybeSingle();
  }

  static Future<void> updateTransaction({
    required String id,
    Map<String, dynamic>? updates,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    if (updates == null || updates.isEmpty) return;

    final prev = await fetchTransactionById(id);
    updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await _client.from('transactions').update(updates).eq('id', id).eq('user_id', uid);

    await ActivityLogger.log(
      eventType: 'transaction_updated',
      summary: 'Updated transaction',
      transactionId: id,
      entityType: 'transaction',
      entityId: id,
      previousState: prev,
    );
  }

  static Future<void> voidTransaction(String id) async {
    await updateTransaction(id: id, updates: {'status': 'voided'});
    await ActivityLogger.log(
      eventType: 'transaction_voided',
      summary: 'Voided transaction',
      transactionId: id,
      entityType: 'transaction',
      entityId: id,
    );
  }

  static Future<List<String>> createFromScanReview({
    required String? documentId,
    required AllocationResult allocation,
    required String date,
    String? categoryId,
    String? categorySource,
    String? paymentMethod,
    String? currency,
    Map<String, dynamic>? extractedData,
  }) async {
    final ids = <String>[];
    for (final draft in allocation.transactions) {
      final txnId = await insertTransaction(
        amount: draft.amount,
        date: date,
        type: draft.type,
        title: draft.title,
        description: draft.description,
        sourceType: draft.sourceType,
        sourceDocumentId: documentId,
        categoryId: categoryId,
        categorySource: categorySource,
        paymentMethod: paymentMethod,
        currency: currency,
        effectiveAmount: draft.effectiveAmount,
        groupId: draft.groupId,
        extractedData: extractedData,
      );
      if (txnId != null) ids.add(txnId);
    }
    return ids;
  }

  // Dashboard aggregation
  static Future<Map<String, dynamic>> dashboardSummary({
    required DateTime weekStart,
    required DateTime weekEnd,
  }) async {
    final uid = _uid;
    if (uid == null) return {'week_spend': 0.0, 'today_spend': 0.0, 'transaction_count': 0};

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final startStr = weekStart.toIso8601String().substring(0, 10);
    final endStr = weekEnd.toIso8601String().substring(0, 10);

    final weekRes = await _client
        .from('transactions')
        .select('effective_amount')
        .eq('user_id', uid)
        .eq('type', 'expense')
        .eq('status', 'confirmed')
        .gte('date', startStr)
        .lte('date', endStr);

    double weekSpend = 0;
    for (final r in weekRes) {
      weekSpend += ((r['effective_amount'] as num?)?.toDouble() ?? 0);
    }

    final todayRes = await _client
        .from('transactions')
        .select('effective_amount')
        .eq('user_id', uid)
        .eq('type', 'expense')
        .eq('status', 'confirmed')
        .eq('date', today);

    double todaySpend = 0;
    for (final r in todayRes) {
      todaySpend += ((r['effective_amount'] as num?)?.toDouble() ?? 0);
    }

    return {
      'week_spend': weekSpend,
      'today_spend': todaySpend,
      'transaction_count': weekRes.length,
    };
  }
}
