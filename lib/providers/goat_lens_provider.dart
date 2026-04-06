import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/goat/statements/goat_analysis_lens.dart';
import '../services/supabase_service.dart';
import 'profile_provider.dart';

/// Current GOAT analysis lens; synced from [profileProvider] and persisted via Supabase.
class GoatAnalysisLensNotifier extends Notifier<GoatAnalysisLens> {
  @override
  GoatAnalysisLens build() {
    final async = ref.watch(profileProvider);
    return async.maybeWhen(
      data: (p) => GoatAnalysisLens.fromDb(p?['goat_analysis_lens'] as String?),
      orElse: () => GoatAnalysisLens.smart,
    );
  }

  Future<void> setLens(GoatAnalysisLens lens) async {
    await SupabaseService.updateProfile(goatAnalysisLens: lens.dbValue);
    ref.invalidate(profileProvider);
    state = lens;
  }
}

final goatAnalysisLensProvider = NotifierProvider<GoatAnalysisLensNotifier, GoatAnalysisLens>(
  GoatAnalysisLensNotifier.new,
);
