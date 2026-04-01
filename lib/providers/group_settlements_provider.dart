import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';

/// Settlements (recorded payments) for one expense group.
final groupSettlementsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, groupId) {
  return SupabaseService.fetchGroupSettlements(groupId);
});
