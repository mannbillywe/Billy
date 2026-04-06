import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/profile_provider.dart';

/// Parses `profiles.goat` defensively (missing column / wrong type → false).
bool parseProfileGoatAccess(Map<String, dynamic>? profile) {
  if (profile == null) return false;
  final g = profile['goat'];
  if (g is bool) return g;
  if (g is String) {
    final s = g.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 't';
  }
  if (g is num) return g != 0;
  return false;
}

/// Whether the signed-in user may see GOAT entry points (false while profile loads).
final goatAccessProvider = Provider<bool>((ref) {
  final async = ref.watch(profileProvider);
  return async.maybeWhen(
    data: parseProfileGoatAccess,
    orElse: () => false,
  );
});
