import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/goat_inputs_models.dart';
import '../services/goat_inputs_service.dart';
import 'goat_providers.dart';

/// One row per user in `goat_user_inputs`. Null when the user has never
/// filled in the setup form.
final goatUserInputsProvider =
    FutureProvider.autoDispose<GoatUserInputs?>((ref) async {
  final hasAccess = ref.watch(goatModeAccessProvider);
  if (!hasAccess) return null;
  return GoatInputsService.fetchUserInputs();
});

final goatGoalsProvider =
    FutureProvider.autoDispose<List<GoatGoal>>((ref) async {
  final hasAccess = ref.watch(goatModeAccessProvider);
  if (!hasAccess) return const [];
  return GoatInputsService.fetchGoals();
});

final goatObligationsProvider =
    FutureProvider.autoDispose<List<GoatObligation>>((ref) async {
  final hasAccess = ref.watch(goatModeAccessProvider);
  if (!hasAccess) return const [];
  return GoatInputsService.fetchObligations();
});

/// Derived: true when the user has filled in at least the minimum required
/// inputs (monthly_income). Used to encourage first-time setup.
final goatSetupCompletedProvider = Provider<bool>((ref) {
  final inputs = ref.watch(goatUserInputsProvider).valueOrNull;
  return inputs?.monthlyIncome != null && inputs!.monthlyIncome! > 0;
});
