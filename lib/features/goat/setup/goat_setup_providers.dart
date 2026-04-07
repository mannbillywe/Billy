import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../providers/profile_provider.dart';
import 'goat_setup_readiness.dart';
import 'goat_setup_repository.dart';

/// Latest row from [goat_setup_state] for the signed-in user.
final goatSetupStateProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return null;
  return GoatSetupRepository.fetchSetupState();
});

/// Deterministic readiness (domain tables + lens).
final goatReadinessProvider = FutureProvider<GoatReadinessResult>((ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) {
    return const GoatReadinessResult(score: 0, criticalMissing: [], optionalMissing: [], nextBestAction: 'Sign in to measure readiness.');
  }
  return GoatSetupReadinessEngine.compute(userId: uid);
});

/// Profile + table counts sent to the Edge function as context.
final setupPrefillProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return GoatSetupRepository.fetchSetupPrefillSnapshot();
});

final goatSetupChecklistProvider = Provider<AsyncValue<List<String>>>((ref) {
  final r = ref.watch(goatReadinessProvider);
  return r.whenData((v) => [...v.criticalMissing, ...v.optionalMissing]);
});

final goatSetupRecommendationsProvider = Provider<AsyncValue<String>>((ref) {
  final r = ref.watch(goatReadinessProvider);
  return r.whenData((v) => v.nextBestAction);
});

int? goatAiCallsUsed(Map<String, dynamic>? setupState) {
  if (setupState == null) return null;
  final meta = setupState['metadata'];
  if (meta is! Map) return 0;
  final raw = meta['ai_calls_used'];
  if (raw is int) return raw;
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

bool goatSetupNeedsResume(Map<String, dynamic>? setupState) {
  if (setupState == null) return false;
  final s = setupState['status'] as String? ?? '';
  return s == 'in_progress';
}

/// Refreshes profile + GOAT setup state after apply.
Future<void> refreshGoatSetupAfterApply(WidgetRef ref) async {
  ref.invalidate(profileProvider);
  ref.invalidate(goatSetupStateProvider);
  ref.invalidate(goatReadinessProvider);
  ref.invalidate(setupPrefillProvider);
}
