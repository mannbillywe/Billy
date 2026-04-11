import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/transaction_service.dart';

final dashboardSummaryProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final now = DateTime.now();
  final weekStart = now.subtract(const Duration(days: 6));
  return TransactionService.dashboardSummary(
    weekStart: weekStart,
    weekEnd: now,
  );
});
