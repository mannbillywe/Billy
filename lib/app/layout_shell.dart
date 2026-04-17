import 'package:file_picker/file_picker.dart';
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
import '../features/goat/screens/goat_mode_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/statements/screens/statement_review_screen.dart';
import '../providers/documents_provider.dart';
import '../providers/groups_provider.dart';
import '../providers/profile_provider.dart';
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
            const SizedBox(height: 10),
            _addOptionTile(
              ctx,
              icon: Icons.table_chart_rounded,
              color: const Color(0xFF8B5CF6),
              bg: const Color(0xFFF3F0FF),
              title: 'Import CSV statement',
              subtitle: 'Import transactions from a bank CSV export',
              onTap: () {
                Navigator.pop(ctx);
                _openCsvImport();
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

  Future<void> _openCsvImport() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the CSV file')),
        );
      }
      return;
    }
    final csvString = String.fromCharCodes(bytes);
    final rows = _parseCsvRows(csvString);
    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No transaction rows found in CSV')),
        );
      }
      return;
    }
    final bankName = file.name.replaceAll('.csv', '').replaceAll('_', ' ');
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => StatementReviewScreen(
          bankName: bankName,
          rows: rows,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _parseCsvRows(String csv) {
    final lines = csv.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 2) return [];
    final header = lines.first.split(',').map((h) => h.trim().toLowerCase()).toList();
    final dateIdx = header.indexWhere((h) => h.contains('date'));
    final descIdx = header.indexWhere((h) => h.contains('desc') || h.contains('narr') || h.contains('vendor') || h.contains('particular'));
    final amountIdx = header.indexWhere((h) => h.contains('amount') || h.contains('debit'));
    if (amountIdx == -1) return [];

    final rows = <Map<String, dynamic>>[];
    for (var i = 1; i < lines.length; i++) {
      final cols = lines[i].split(',');
      if (cols.length <= amountIdx) continue;
      final amtStr = cols[amountIdx].replaceAll(RegExp(r'[^0-9.\-]'), '');
      final amount = double.tryParse(amtStr);
      if (amount == null || amount == 0) continue;
      rows.add({
        'date': dateIdx >= 0 && cols.length > dateIdx ? cols[dateIdx].trim() : '',
        'vendor': descIdx >= 0 && cols.length > descIdx ? cols[descIdx].trim() : 'Unknown',
        'amount': amount,
        'matched': false,
      });
    }
    return rows;
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
    ).then((_) {
      ref.invalidate(profileProvider);
    });
  }

  void _openGoatMode() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GoatModeScreen()),
    );
  }

  void _switchToTab(int index) {
    setState(() => _activeTab = index);
  }

  Widget _buildContent() {
    switch (_activeTab) {
      case 0:
        return DashboardScreen(
          onExportData: _openExport,
          onCreateBill: _openAddExpense,
          onOpenAllDocuments: _openDocumentHistory,
          onOpenDocumentDetail: _openDocumentDetail,
          onSwitchToPlan: () => _switchToTab(3),
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
          onExportData: _openExport,
          onCreateBill: _openAddExpense,
          onOpenAllDocuments: _openDocumentHistory,
          onOpenDocumentDetail: _openDocumentDetail,
          onSwitchToPlan: () => _switchToTab(3),
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
            BillyHeader(onOpenSettings: _openSettings, onOpenGoatMode: _openGoatMode),
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
