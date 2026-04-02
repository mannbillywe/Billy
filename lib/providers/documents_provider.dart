import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';

class DocumentsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() => SupabaseService.fetchDocuments();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => SupabaseService.fetchDocuments());
  }

  Future<void> addDocument({
    required String vendorName,
    required double amount,
    required double taxAmount,
    required String date,
    String type = 'receipt',
    String? description,
    String? paymentMethod,
    String? currency,
    Map<String, dynamic>? extractedData,
  }) async {
    await SupabaseService.insertDocument(
      vendorName: vendorName,
      amount: amount,
      taxAmount: taxAmount,
      date: date,
      type: type,
      description: description,
      paymentMethod: paymentMethod,
      currency: currency,
      extractedData: extractedData,
    );
    await refresh();
  }

  Future<void> deleteDoc(String id) async {
    await SupabaseService.deleteDocument(id);
    await refresh();
  }

  Future<void> updateDocument({
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
  }) async {
    await SupabaseService.updateDocument(
      id: id,
      vendorName: vendorName,
      amount: amount,
      taxAmount: taxAmount,
      date: date,
      type: type,
      description: description,
      paymentMethod: paymentMethod,
      currency: currency,
      extractedData: extractedData,
    );
    await refresh();
  }
}

final documentsProvider =
    AsyncNotifierProvider<DocumentsNotifier, List<Map<String, dynamic>>>(DocumentsNotifier.new);

// Dashboard aggregations
final todaySpendProvider = FutureProvider<double>((ref) => SupabaseService.todaySpend());

final weekSpendProvider = FutureProvider<double>((ref) {
  final now = DateTime.now();
  final weekday = now.weekday;
  final start = now.subtract(Duration(days: weekday - 1));
  return SupabaseService.weekSpend(weekStart: start, weekEnd: now);
});

final lastWeekSpendProvider = FutureProvider<double>((ref) {
  final now = DateTime.now();
  final weekday = now.weekday;
  final thisWeekStart = now.subtract(Duration(days: weekday - 1));
  final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
  final lastWeekEnd = thisWeekStart.subtract(const Duration(days: 1));
  return SupabaseService.weekSpend(weekStart: lastWeekStart, weekEnd: lastWeekEnd);
});

final recentDocsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(documentsProvider);
  return SupabaseService.recentDocuments(limit: 10);
});

final dailySpendProvider = FutureProvider<List<double>>((ref) {
  ref.watch(documentsProvider);
  return SupabaseService.dailySpendForWeek();
});
