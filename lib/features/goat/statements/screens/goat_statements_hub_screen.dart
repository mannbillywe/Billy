import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/goat_theme.dart';
import '../../../../providers/documents_provider.dart';
import '../../../../providers/goat_statements_providers.dart';
import '../../../../providers/profile_provider.dart';
import '../../widgets/goat_premium_card.dart';
import 'goat_ledger_documents_screen.dart';
import 'goat_statements_subscreens.dart';
import 'statement_upload_wizard_screen.dart';

/// GOAT Statements home: entry to import, lists, analytics.
class GoatStatementsHubScreen extends ConsumerWidget {
  const GoatStatementsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR';
    final importsAsync = ref.watch(statementImportsProvider);
    final txAsync = ref.watch(statementTransactionsProvider);
    final linksAsync = ref.watch(statementDocumentLinksProvider);

    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Statements'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StatementUploadWizardScreen()),
            );
          },
          backgroundColor: GoatTokens.gold,
          foregroundColor: GoatTokens.background,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Import'),
        ),
        body: RefreshIndicator(
          color: GoatTokens.gold,
          onRefresh: () async {
            ref.invalidate(statementImportsProvider);
            ref.invalidate(statementTransactionsProvider);
            ref.invalidate(statementAccountsProvider);
            ref.invalidate(statementDocumentLinksProvider);
            ref.invalidate(canonicalFinancialEventsProvider);
            ref.invalidate(statementImportReviewsProvider);
            ref.invalidate(documentsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              Text(
                'Bank & card statements',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: GoatTokens.textPrimary,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Deterministic parsing and dedupe. AI may suggest mappings later — never silent truth.',
                style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 20),
              importsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (imps) {
                  final last = imps.isNotEmpty ? imps.first : null;
                  final txCount = txAsync.valueOrNull?.length ?? 0;
                  final linkCount = linksAsync.valueOrNull?.length ?? 0;
                  return GoatPremiumCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Snapshot', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
                        const SizedBox(height: 8),
                        Text('$txCount statement transactions', style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w800, fontSize: 18)),
                        Text('$linkCount document links', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
                        if (last != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Latest: ${last['file_name']} · ${last['import_status']}',
                            style: TextStyle(color: GoatTokens.textPrimary, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text('Navigate', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _tile(context, 'Receipts in GOAT', 'Include / exclude from Smart, delete', Icons.description_outlined, () {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GoatLedgerDocumentsScreen()));
              }),
              _tile(context, 'Transactions', 'Filters & badges', Icons.receipt_long_outlined, () {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StatementTransactionsScreen()));
              }),
              _tile(context, 'Imports', 'History & status', Icons.folder_open_outlined, () {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StatementImportsScreen()));
              }),
              _tile(context, 'Import reviews', 'Parser & dedupe queue', Icons.flag_outlined, () {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StatementImportReviewsScreen()));
              }),
              _tile(context, 'Duplicates & links', 'Review matches', Icons.link_outlined, () {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StatementDuplicatesScreen()));
              }),
              _tile(context, 'Accounts', 'Statement-derived', Icons.account_balance_outlined, () {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StatementAccountsScreen()));
              }),
              _tile(context, 'Statement analytics', 'Flows & merchants', Icons.insights_outlined, () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => StatementAnalyticsScreen(currency: currency)),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _tile(BuildContext context, String title, String sub, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GoatPremiumCard(
        onTap: onTap,
        accentBorder: false,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: GoatTokens.gold.withValues(alpha: 0.9)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700)),
                  Text(sub, style: TextStyle(color: GoatTokens.textMuted, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: GoatTokens.textMuted),
          ],
        ),
      ),
    );
  }
}
