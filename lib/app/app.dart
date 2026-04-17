import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/billy_theme.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/goat/providers/goat_mode_providers.dart';
import '../features/goat/providers/goat_setup_providers.dart';
import '../providers/activity_feed_provider.dart';
import '../providers/budgets_provider.dart';
import '../providers/disputes_provider.dart';
import '../providers/documents_provider.dart';
import '../providers/group_expenses_provider.dart';
import '../providers/group_settlements_provider.dart';
import '../providers/groups_provider.dart';
import '../providers/lend_borrow_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/recurring_provider.dart';
import '../providers/recurring_suggestions_provider.dart';
import '../providers/social_provider.dart';
import '../providers/suggestions_provider.dart';
import '../providers/transactions_provider.dart';
import '../providers/usage_limits_provider.dart';
import 'layout_shell.dart';

final _navKey = GlobalKey<NavigatorState>();

/// Invalidate every user-scoped provider so signing in as a different account
/// doesn't leak the previous user's cached data (documents, transactions,
/// profile, groups, goat state, …).
void _resetUserScopedProviders(WidgetRef ref) {
  ref.invalidate(profileProvider);
  ref.invalidate(documentsProvider);
  ref.invalidate(transactionsProvider);
  ref.invalidate(lendBorrowProvider);
  ref.invalidate(budgetsProvider);
  ref.invalidate(expenseGroupsNotifierProvider);
  ref.invalidate(activityFeedProvider);
  ref.invalidate(suggestionsProvider);
  ref.invalidate(recurringSeriesProvider);
  ref.invalidate(recurringSuggestionsProvider);
  ref.invalidate(invitationsNotifierProvider);
  ref.invalidate(connectionsNotifierProvider);
  ref.invalidate(usageLimitsProvider);
  ref.invalidate(goatModeControllerProvider);
  ref.invalidate(goatUserInputsControllerProvider);
  ref.invalidate(goatGoalsControllerProvider);
  ref.invalidate(goatObligationsControllerProvider);
  // Family providers: invalidating the family drops every keyed variant.
  ref.invalidate(disputesProvider);
  ref.invalidate(groupExpensesProvider);
  ref.invalidate(groupSettlementsProvider);
}

class BillyApp extends ConsumerWidget {
  const BillyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);

    ref.listen<AsyncValue<dynamic>>(authStateProvider, (prev, next) {
      final prevUserId = prev?.valueOrNull?.id as String?;
      final nextUserId = next.valueOrNull?.id as String?;
      final wasLoggedIn = prevUserId != null;
      final isLoggedIn = nextUserId != null;
      final userChanged = prevUserId != nextUserId;

      // Any auth transition (sign-in, sign-out, user swap) must drop cached
      // per-user state before we repaint — otherwise the next user sees the
      // previous user's documents/profile until a manual refresh.
      if (userChanged) {
        _resetUserScopedProviders(ref);
      }

      if (wasLoggedIn && !isLoggedIn) {
        _navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      } else if (!wasLoggedIn && isLoggedIn) {
        _navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const LayoutShell()),
          (_) => false,
        );
      }
    });

    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Billy',
      debugShowCheckedModeBanner: false,
      theme: BillyTheme.lightTheme,
      home: authAsync.when(
        data: (user) => user != null ? const LayoutShell() : const LoginScreen(),
        loading: () => const Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: CircularProgressIndicator(color: BillyTheme.emerald600),
          ),
        ),
        error: (e, st) => const LoginScreen(),
      ),
    );
  }
}
