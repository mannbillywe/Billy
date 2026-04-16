import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';

final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) => SupabaseService.fetchProfile());

/// Whether GOAT Mode should be shown (from [profiles.goat_mode], set in Supabase).
bool profileGoatModeEnabled(Map<String, dynamic>? profile) {
  if (profile == null) return false;
  final v = profile['goat_mode'];
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  return false;
}
