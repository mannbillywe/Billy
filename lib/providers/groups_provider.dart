import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';

class ExpenseGroupsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() => SupabaseService.fetchExpenseGroups();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(SupabaseService.fetchExpenseGroups);
  }

  Future<String> createGroup(String name) async {
    final row = await SupabaseService.createExpenseGroup(name: name);
    await refresh();
    return row['id'] as String;
  }

  Future<void> addMember({required String groupId, required String memberUserId}) async {
    await SupabaseService.addUserToExpenseGroup(groupId: groupId, memberUserId: memberUserId);
    await refresh();
  }
}

final expenseGroupsNotifierProvider =
    AsyncNotifierProvider<ExpenseGroupsNotifier, List<Map<String, dynamic>>>(ExpenseGroupsNotifier.new);
