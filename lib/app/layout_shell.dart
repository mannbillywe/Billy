import 'package:flutter/material.dart';

import '../core/theme/billy_theme.dart';
import '../features/analytics/screens/analytics_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/dashboard/widgets/add_expense_sheet.dart';
import '../features/lend_borrow/screens/split_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import 'widgets/billy_bottom_nav.dart';
import 'widgets/billy_header.dart';

class LayoutShell extends StatefulWidget {
  const LayoutShell({super.key});

  @override
  State<LayoutShell> createState() => _LayoutShellState();
}

class _LayoutShellState extends State<LayoutShell> {
  int _activeTab = 0;

  void _openAddExpense() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AddExpenseSheet(),
    );
  }

  Widget _buildContent() {
    switch (_activeTab) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const AnalyticsScreen();
      case 2:
        return const SplitScreen();
      case 3:
        return const SettingsScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            const BillyHeader(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: _buildContent(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BillyBottomNav(
        activeIndex: _activeTab,
        onTap: (i) => setState(() => _activeTab = i),
        onFabTap: _openAddExpense,
      ),
    );
  }
}
