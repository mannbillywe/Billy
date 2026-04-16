import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// Streams changes on `auth.users` — invalidates the cached profile whenever the
/// session changes (sign-in, sign-up, token refresh, sign-out).
final _authUserStream = StreamProvider<User?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange.map((e) => e.session?.user);
});

/// User profile from `profiles` table. Re-fetched whenever auth state changes
/// (so a sign-out + sign-in, or token refresh, triggers a fresh read).
/// Force a manual refresh anywhere with `ref.invalidate(profileProvider)`.
final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) {
  ref.watch(_authUserStream);
  return SupabaseService.fetchProfile();
});

/// Whether GOAT Mode should be shown (from [profiles.goat_mode], set in Supabase).
bool profileGoatModeEnabled(Map<String, dynamic>? profile) {
  if (profile == null) {
    if (kDebugMode) debugPrint('[GOAT] profile is null — hiding GOAT button');
    return false;
  }
  final v = profile['goat_mode'];
  final enabled = v == true || (v is String && v.toLowerCase() == 'true');
  if (kDebugMode) {
    debugPrint('[GOAT] goat_mode raw=$v (${v.runtimeType}) → enabled=$enabled');
  }
  return enabled;
}
