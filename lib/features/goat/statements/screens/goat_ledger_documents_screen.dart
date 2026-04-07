import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatting/app_currency.dart';
import '../../../../core/theme/goat_theme.dart';
import '../../../../providers/documents_provider.dart';
import '../../../../providers/goat_cash_providers.dart' show goatForecastProvider;
import '../../../../providers/goat_statements_providers.dart';
import '../../../../providers/profile_provider.dart';
import '../../../../services/supabase_service.dart';
import '../../widgets/goat_premium_card.dart';

/// Billy ledger documents with GOAT Smart lens inclusion toggle (exclude_from_goat_smart_analytics).
class GoatLedgerDocumentsScreen extends ConsumerWidget {
  const GoatLedgerDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR';
    final async = ref.watch(documentsProvider);

    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Receipts in GOAT'),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
          error: (e, _) => Center(child: Text('$e', style: TextStyle(color: GoatTokens.textMuted))),
          data: (docs) {
            final saved = docs.where((d) => (d['status'] as String?) != 'draft').toList()
              ..sort((a, b) {
                final da = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(1970);
                final db = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(1970);
                return db.compareTo(da);
              });
            if (saved.isEmpty) {
              return Center(
                child: Text(
                  'No saved documents yet. Add receipts from the main Billy flow.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GoatTokens.textMuted, height: 1.4),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Use the switch to include or exclude each receipt in the Smart lens. '
                  'Excluded items stay in your ledger but do not double-count with statement imports.',
                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 12),
                ...saved.map((d) {
                  final id = d['id'] as String?;
                  final vendor = d['vendor_name'] as String? ?? 'Document';
                  final date = d['date']?.toString() ?? '';
                  final amt = (d['amount'] as num?)?.toDouble() ?? 0;
                  final excluded = d['exclude_from_goat_smart_analytics'] == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GoatPremiumCard(
                      accentBorder: false,
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vendor,
                                  style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$date · ${AppCurrency.format(amt, currency)}',
                                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                                ),
                                Text(
                                  excluded ? 'Excluded from Smart lens' : 'Counts in Smart lens',
                                  style: TextStyle(color: excluded ? const Color(0xFFFBBF24) : GoatTokens.gold, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: !excluded,
                            activeThumbColor: GoatTokens.gold,
                            onChanged: id == null
                                ? null
                                : (includeInSmart) async {
                                    final exclude = !includeInSmart;
                                    try {
                                      await SupabaseService.updateDocument(
                                        id: id,
                                        excludeFromGoatSmartAnalytics: exclude,
                                      );
                                      await ref.read(documentsProvider.notifier).refresh();
                                      ref.invalidate(goatLensWeekDebitSpendProvider);
                                      ref.invalidate(goatForecastProvider);
                                      ref.invalidate(statementDocumentLinksProvider);
                                      ref.invalidate(canonicalFinancialEventsProvider);
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Could not update: $e')),
                                        );
                                      }
                                    }
                                  },
                          ),
                          if (id != null)
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: GoatTokens.textMuted),
                              color: GoatTokens.surface,
                              surfaceTintColor: Colors.transparent,
                              onSelected: (v) async {
                                if (v != 'delete') return;
                                final go = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: GoatTokens.surface,
                                    title: Text('Delete document?', style: TextStyle(color: GoatTokens.textPrimary)),
                                    content: Text(
                                      'This removes the receipt from your Billy ledger (not undoable).',
                                      style: TextStyle(color: GoatTokens.textMuted, height: 1.35),
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
                                  try {
                                    await ref.read(documentsProvider.notifier).deleteDoc(id);
                                    ref.invalidate(goatLensWeekDebitSpendProvider);
                                    ref.invalidate(goatForecastProvider);
                                    ref.invalidate(statementDocumentLinksProvider);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Delete failed: $e')),
                                      );
                                    }
                                  }
                                }
                              },
                              itemBuilder: (ctx) => [
                                PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Text('Delete from Billy', style: TextStyle(color: const Color(0xFFFCA5A5))),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}
