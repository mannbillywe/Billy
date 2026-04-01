import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';

/// Expenses for one [expense_groups] id. Invalidate after mutations.
final groupExpensesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, groupId) {
  return SupabaseService.fetchGroupExpenses(groupId);
});
