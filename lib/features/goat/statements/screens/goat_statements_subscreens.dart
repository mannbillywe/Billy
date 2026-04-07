import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatting/app_currency.dart';
import '../../../../core/theme/goat_theme.dart';
import '../../../../providers/goat_cash_providers.dart' show goatForecastProvider;
import '../../../../providers/goat_statements_providers.dart';
import '../../../../providers/profile_provider.dart';
import '../../widgets/goat_premium_card.dart';
import '../statement_repository.dart';
import '../statement_recurring_detection.dart';
import 'statement_transaction_detail_screen.dart';

class StatementTransactionsScreen extends ConsumerWidget {
  const StatementTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR';
    final async = ref.watch(statementTransactionsProvider);
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Statement transactions'),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
          error: (e, _) => Center(child: Text('$e', style: TextStyle(color: GoatTokens.textMuted))),
          data: (rows) {
            if (rows.isEmpty) {
              return Center(child: Text('No transactions yet.', style: TextStyle(color: GoatTokens.textMuted)));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final t = rows[i];
                final linked = t['metadata'] is Map && (t['metadata'] as Map)['linked'] == true;
                final id = t['id'] as String?;
                return GoatPremiumCard(
                  accentBorder: false,
                  padding: const EdgeInsets.all(12),
                  onTap: id == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => StatementTransactionDetailScreen(transactionId: id),
                            ),
                          );
                        },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t['description_raw'] as String? ?? '',
                              style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${t['direction'] == 'debit' ? '-' : '+'}${AppCurrency.format((t['amount'] as num?)?.toDouble() ?? 0, currency)}',
                            style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      Text(
                        '${t['txn_date']} · ${t['status']}',
                        style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                      ),
                      if (linked)
                        Text('Linked receipt', style: TextStyle(color: GoatTokens.gold, fontSize: 10)),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class StatementImportsScreen extends ConsumerWidget {
  const StatementImportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(statementImportsProvider);
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Import history'),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
          error: (e, _) => Center(child: Text('$e')),
          data: (rows) {
            if (rows.isEmpty) {
              return Center(child: Text('No imports yet.', style: TextStyle(color: GoatTokens.textMuted)));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = rows[i];
                final importId = r['id'] as String?;
                return GoatPremiumCard(
                  accentBorder: false,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              r['file_name'] as String? ?? '',
                              style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (importId != null)
                            IconButton(
                              tooltip: 'Delete import',
                              icon: Icon(Icons.delete_outline, color: const Color(0xFFFCA5A5), size: 22),
                              onPressed: () async {
                                final go = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: GoatTokens.surface,
                                    title: Text('Delete this import?', style: TextStyle(color: GoatTokens.textPrimary)),
                                    content: Text(
                                      'Removes the import record and all statement rows tied to it (cascade). '
                                      'The file may remain in storage.',
                                      style: TextStyle(color: GoatTokens.textMuted, fontSize: 13, height: 1.35),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (go == true && context.mounted) {
                                  await StatementRepository.deleteImport(importId);
                                  ref.invalidate(statementImportsProvider);
                                  ref.invalidate(statementTransactionsProvider);
                                  ref.invalidate(statementAccountsProvider);
                                  ref.invalidate(statementDocumentLinksProvider);
                                  ref.invalidate(canonicalFinancialEventsProvider);
                                  ref.invalidate(statementImportReviewsProvider);
                                  ref.invalidate(goatLensWeekDebitSpendProvider);
                                  ref.invalidate(goatForecastProvider);
                                }
                              },
                            ),
                        ],
                      ),
                      Text(
                        '${r['import_status']} · ${r['transaction_count']} rows · ${(r['parse_confidence'] as num?)?.toStringAsFixed(0) ?? '—'}% conf',
                        style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class StatementImportReviewsScreen extends ConsumerWidget {
  const StatementImportReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(statementImportReviewsProvider);
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Import reviews'),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
          error: (e, _) => Center(child: Text('$e')),
          data: (rows) {
            if (rows.isEmpty) {
              return Center(
                child: Text(
                  'No review queue items. Low-confidence parses and weak dedupe matches appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GoatTokens.textMuted, height: 1.4),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = rows[i];
                final id = r['id'] as String?;
                final resolved = r['resolved'] == true;
                return GoatPremiumCard(
                  accentBorder: false,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['review_type'] as String? ?? '', style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w700)),
                      Text(
                        'Import ${r['import_id'] ?? '—'}',
                        style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                      ),
                      Text(
                        r['payload'].toString(),
                        style: TextStyle(color: GoatTokens.textPrimary, fontSize: 11, height: 1.35),
                      ),
                      if (id != null)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Resolved', style: TextStyle(color: GoatTokens.textPrimary, fontSize: 13)),
                          value: resolved,
                          activeThumbColor: GoatTokens.gold,
                          onChanged: (v) async {
                            await StatementRepository.setImportReviewResolved(id, resolved: v);
                            ref.invalidate(statementImportReviewsProvider);
                          },
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class StatementDuplicatesScreen extends ConsumerWidget {
  const StatementDuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(statementDocumentLinksProvider);
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Duplicates & links'),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
          error: (e, _) => Center(child: Text('$e')),
          data: (rows) {
            if (rows.isEmpty) {
              return Center(
                child: Text(
                  'No links yet. Smart imports create matches automatically; review scores here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GoatTokens.textMuted, height: 1.4),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = rows[i];
                return GoatPremiumCard(
                  accentBorder: false,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Match: ${r['match_type']}', style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w700)),
                      Text('Score ${r['score']}', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
                      Text(
                        'Stmt txn ${r['statement_transaction_id']}\nDoc ${r['document_id']}',
                        style: TextStyle(color: GoatTokens.textPrimary, fontSize: 11, height: 1.35),
                      ),
                      Text(
                        'Exclude double-count: ${r['is_excluded_from_double_count']}',
                        style: TextStyle(color: GoatTokens.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class StatementAccountsScreen extends ConsumerWidget {
  const StatementAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(statementAccountsProvider);
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Statement accounts'),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
          error: (e, _) => Center(child: Text('$e')),
          data: (rows) {
            if (rows.isEmpty) {
              return Center(child: Text('No accounts yet — import a statement.', style: TextStyle(color: GoatTokens.textMuted)));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = rows[i];
                return GoatPremiumCard(
                  accentBorder: false,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['account_name'] as String? ?? '', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700)),
                      Text('${r['account_type']} · ${r['currency']}', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class StatementAnalyticsScreen extends ConsumerWidget {
  const StatementAnalyticsScreen({super.key, required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(statementTransactionsProvider);
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Statement analytics'),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
          error: (e, _) => Center(child: Text('$e')),
          data: (rows) {
            var debit = 0.0;
            var credit = 0.0;
            final merchants = <String, double>{};
            for (final t in rows) {
              if ((t['status'] as String?) != 'active') continue;
              final a = (t['amount'] as num?)?.toDouble() ?? 0;
              if (t['direction'] == 'debit') {
                debit += a;
                final d = (t['description_raw'] as String? ?? 'Unknown').split(' ').take(4).join(' ');
                merchants[d] = (merchants[d] ?? 0) + a;
              } else {
                credit += a;
              }
            }
            final top = merchants.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            final recurring = StatementRecurringDetection.fromTransactions(rows, minHits: 3);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                GoatPremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cash movement (all imported rows)', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text('Out (debit): ${AppCurrency.format(debit, currency)}', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700)),
                      Text('In (credit): ${AppCurrency.format(credit, currency)}', style: TextStyle(color: GoatTokens.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Recurring-like debits', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'Same normalized description ≥3 times (deterministic; not verified subscriptions).',
                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.35),
                ),
                const SizedBox(height: 8),
                if (recurring.isEmpty)
                  Text('No strong patterns yet.', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12))
                else
                  ...recurring.take(10).map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: GoatPremiumCard(
                            accentBorder: false,
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    c.label,
                                    style: TextStyle(color: GoatTokens.textPrimary, fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${c.hitCount}× · ${AppCurrency.format(c.totalAmount, currency)}',
                                  style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w600, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                const SizedBox(height: 16),
                Text('Top descriptions', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...top.take(12).map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: GoatPremiumCard(
                          accentBorder: false,
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Expanded(child: Text(e.key, style: TextStyle(color: GoatTokens.textPrimary, fontSize: 12))),
                              Text(AppCurrency.format(e.value, currency), style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
