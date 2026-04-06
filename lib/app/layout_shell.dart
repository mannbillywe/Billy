import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/billy_theme.dart';
import '../features/analytics/screens/analytics_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/dashboard/widgets/add_expense_sheet.dart';
import '../features/documents/screens/document_detail_screen.dart';
import '../features/documents/screens/documents_history_screen.dart';
import '../features/export/models/export_document.dart';
import '../features/export/screens/export_screen.dart';
import '../features/lend_borrow/screens/split_screen.dart';
import '../features/scanner/screens/scan_screen.dart';
import '../features/goat/screens/goat_shell_screen.dart';
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

  void _openGoatMode() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GoatShellScreen()),
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
          onOpenGoatMode: _openGoatMode,
        );
      case 1:
        return const AnalyticsScreen();
      case 2:
        return const SplitScreen();
      case 3:
        return const SettingsScreen();
      default:
        return DashboardScreen(
          onOpenScan: _openScan,
          onExportData: _openExport,
          onCreateBill: _openAddExpense,
          onOpenAllDocuments: _openDocumentHistory,
          onOpenDocumentDetail: _openDocumentDetail,
          onOpenGoatMode: _openGoatMode,
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
            BillyHeader(onOpenGoatMode: _openGoatMode),
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
