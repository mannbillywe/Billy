import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';

class LendBorrowNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() => SupabaseService.fetchLendBorrow();

  /// Avoid setting bare [AsyncLoading] — it clears [valueOrNull] and zeros totals/list until fetch returns.
  Future<void> refresh() async {
    state = await AsyncValue.guard(() => SupabaseService.fetchLendBorrow());
  }

  Future<void> addEntry({
    required String counterpartyName,
    required double amount,
    required String type,
    String? notes,
    String? counterpartyUserId,
    String? groupId,
    String? documentId,
  }) async {
    await SupabaseService.insertLendBorrow(
      counterpartyName: counterpartyName,
      amount: amount,
      type: type,
      notes: notes,
      counterpartyUserId: counterpartyUserId,
      groupId: groupId,
      documentId: documentId,
    );
    await refresh();
  }

  Future<void> settle(String id) async {
    await SupabaseService.settleLendBorrow(id);
    await refresh();
  }

  Future<void> remove(String id) async {
    await SupabaseService.deleteLendBorrow(id);
    await refresh();
  }
}

final lendBorrowProvider =
    AsyncNotifierProvider<LendBorrowNotifier, List<Map<String, dynamic>>>(LendBorrowNotifier.new);
