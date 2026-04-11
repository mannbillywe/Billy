import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/billy_theme.dart';
import '../features/activity/screens/activity_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/dashboard/widgets/add_expense_sheet.dart';
import '../features/documents/screens/document_detail_screen.dart';
import '../features/documents/screens/documents_history_screen.dart';
import '../features/export/models/export_document.dart';
import '../features/export/screens/export_screen.dart';
import '../features/analytics/screens/analytics_screen.dart';
import '../features/lend_borrow/screens/split_screen.dart';
import '../features/planning/screens/plan_screen.dart';
import '../features/scanner/screens/scan_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../providers/documents_provider.dart';
import '../providers/groups_provider.dart';
import '../providers/social_provider.dart';
import 'widgets/billy_bottom_nav.dart';
import 'widgets/billy_header.dart';

class LayoutShell extends ConsumerStatefulWidget {
  const LayoutShell({super.key});

  @override
  ConsumerState<LayoutShell> createState() => _LayoutShellState();
}

class _LayoutShellState extends ConsumerState<LayoutShell> {
  int _activeTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(invitationsNotifierProvider.notifier).refresh();
      ref.read(connectionsNotifierProvider.notifier).refresh();
      ref.read(expenseGroupsNotifierProvider.notifier).refresh();
    });
  }

  void _openAddExpense() {
    _showAddOptions();
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text('Add expense', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
            const SizedBox(height: 4),
            const Text('Choose how to add', style: TextStyle(fontSize: 13, color: BillyTheme.gray500)),
            const SizedBox(height: 20),
            _addOptionTile(
              ctx,
              icon: Icons.camera_alt_rounded,
              color: BillyTheme.emerald600,
              bg: BillyTheme.emerald50,
              title: 'Scan receipt / invoice',
              subtitle: 'Use camera or gallery to extract data with AI',
              onTap: () { Navigator.pop(ctx); _openScan(); },
            ),
            const SizedBox(height: 10),
            _addOptionTile(
              ctx,
              icon: Icons.edit_note_rounded,
              color: BillyTheme.blue400,
              bg: const Color(0xFFEFF6FF),
              title: 'Manual entry',
              subtitle: 'Type in vendor, amount, category manually',
              onTap: () {
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                  builder: (_) => const AddExpenseSheet(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _addOptionTile(BuildContext ctx, {required IconData icon, required Color color, required Color bg, required String title, required String subtitle, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BillyTheme.gray100),
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: BillyTheme.gray500)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: BillyTheme.gray300),
            ],
          ),
        ),
      ),
    );
  }

  void _openScan() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('Scan invoice'),
            backgroundColor: BillyTheme.scaffoldBg,
            foregroundColor: BillyTheme.gray800,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(ctx).maybePop(),
            ),
          ),
          backgroundColor: BillyTheme.scaffoldBg,
          body: const ScanScreen(),
        ),
      ),
    );
  }

  void _openDocumentHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DocumentsHistoryScreen()),
    );
  }

  void _openDocumentDetail(String documentId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentDetailScreen(documentId: documentId),
      ),
    );
  }

  void _openExport() {
    final docs = ref.read(documentsProvider).valueOrNull ?? [];
    final exportDocs = documentsForExport(docs);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ExportScreen(documents: exportDocs)),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  Widget _buildContent() {
    switch (_activeTab) {
      case 0:
        return DashboardScreen(
          onOpenScan: _openScan,
          onExportData: _openExport,
          onCreateBill: _openAddExpense,
          onOpenAllDocuments: _openDocumentHistory,
          onOpenDocumentDetail: _openDocumentDetail,
        );
      case 1:
        return const ActivityScreen();
      case 2:
        return const SplitScreen();
      case 3:
        return const PlanScreen();
      case 4:
        return const AnalyticsScreen();
      default:
        return DashboardScreen(
          onOpenScan: _openScan,
          onExportData: _openExport,
          onCreateBill: _openAddExpense,
          onOpenAllDocuments: _openDocumentHistory,
          onOpenDocumentDetail: _openDocumentDetail,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            BillyHeader(onOpenSettings: _openSettings),
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
        onFabTap: _openScan,
      ),
    );
  }
}
