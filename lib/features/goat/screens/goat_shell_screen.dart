import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/telemetry/goat_telemetry.dart';
import '../../../core/theme/goat_theme.dart';
import '../../../providers/profile_provider.dart';
import '../goat_profile.dart';
import '../widgets/goat_analysis_lens_bar.dart';
import '../widgets/goat_header_banner.dart';
import 'goat_profile_gate_screens.dart';
import '../statements/screens/goat_statements_hub_screen.dart';
import 'goat_forecast_screen.dart';
import 'goat_goals_screen.dart';
import 'goat_home_tab.dart';
import 'goat_preferences_screen.dart';
import 'goat_recurring_screen.dart';
import '../setup/screens/goat_setup_screen.dart';

/// Premium GOAT workspace shell (separate from main Billy chrome).
class GoatShellScreen extends ConsumerStatefulWidget {
  const GoatShellScreen({super.key});

  @override
  ConsumerState<GoatShellScreen> createState() => _GoatShellScreenState();
}

class _GoatShellScreenState extends ConsumerState<GoatShellScreen> {
  int _tab = 0;
  bool _openedLogged = false;

  static const _labels = ['Home', 'Recurring', 'Forecast', 'Goals', 'Prefs'];

  void _setTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    logGoatEvent('goat_module_opened', {'module': _labels[i]});
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      loading: () => Theme(
        data: GoatTheme.darkTheme(context),
        child: const Scaffold(
          backgroundColor: GoatTokens.background,
          body: Center(
            child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => GoatProfileLoadErrorScreen(
        onBack: () => Navigator.of(context).maybePop(),
        detail: e.toString(),
      ),
      data: (profile) {
        if (profile == null) {
          return GoatProfileMissingScreen(onBack: () => Navigator.of(context).maybePop());
        }
        if (!parseProfileGoatAccess(profile)) {
          return GoatAccessDeniedScreen(onBack: () => Navigator.of(context).maybePop());
        }

        if (!_openedLogged) {
          _openedLogged = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            logGoatEvent('goat_mode_opened');
          });
        }

        return Theme(
          data: GoatTheme.darkTheme(context),
          child: Scaffold(
            backgroundColor: GoatTokens.background,
            body: Column(
              children: [
                GoatHeaderBanner(
                  onExit: () => Navigator.of(context).maybePop(),
                  onOpenStatements: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const GoatStatementsHubScreen()),
                    );
                  },
                  onOpenSetup: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const GoatSetupScreen()),
                    );
                  },
                ),
                const GoatAnalysisLensBar(),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      GoatHomeTab(onNavigateToModule: _setTab),
                      const GoatRecurringScreen(),
                      const GoatForecastScreen(),
                      const GoatGoalsScreen(),
                      const GoatPreferencesScreen(),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _setTab,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
                NavigationDestination(
                  icon: Icon(Icons.event_repeat_outlined),
                  selectedIcon: Icon(Icons.event_repeat_rounded),
                  label: 'Recurring',
                ),
                NavigationDestination(
                  icon: Icon(Icons.show_chart_outlined),
                  selectedIcon: Icon(Icons.show_chart_rounded),
                  label: 'Forecast',
                ),
                NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag_rounded), label: 'Goals'),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune_rounded),
                  label: 'Prefs',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
