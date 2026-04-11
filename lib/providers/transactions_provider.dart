import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/transaction_service.dart';

class TransactionsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    return TransactionService.fetchTransactions();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => TransactionService.fetchTransactions());
  }

  Future<String?> addTransaction({
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
    double? effectiveAmount,
    String? groupId,
    String? groupExpenseId,
    String? lendBorrowId,
    String? notes,
    Map<String, dynamic>? extractedData,
    String status = 'confirmed',
  }) async {
    final id = await TransactionService.insertTransaction(
      amount: amount,
      date: date,
      type: type,
      title: title,
      sourceType: sourceType,
      description: description,
      categoryId: categoryId,
      categorySource: categorySource,
      paymentMethod: paymentMethod,
      currency: currency,
      sourceDocumentId: sourceDocumentId,
      effectiveAmount: effectiveAmount,
      groupId: groupId,
      groupExpenseId: groupExpenseId,
      lendBorrowId: lendBorrowId,
      notes: notes,
      extractedData: extractedData,
      status: status,
    );
    await refresh();
    return id;
  }

  Future<void> voidTransaction(String id) async {
    await TransactionService.voidTransaction(id);
    await refresh();
  }
}

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<Map<String, dynamic>>>(
  TransactionsNotifier.new,
);
