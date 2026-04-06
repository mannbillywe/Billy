import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/formatting/app_currency.dart';
import '../../../../core/theme/goat_theme.dart';
import '../../../../providers/goat_cash_providers.dart' show goatForecastProvider;
import '../../../../providers/goat_statements_providers.dart';
import '../../../../providers/profile_provider.dart';
import '../../../documents/screens/document_detail_screen.dart';
import '../../widgets/goat_premium_card.dart';
import '../statement_repository.dart';

const _kTxnTypes = <String>[
  'purchase',
  'atm',
  'transfer',
  'fee',
  'interest',
  'refund',
  'income',
  'payment',
  'emi',
  'subscription',
  'cash',
  'other',
];

const _kStatuses = <String>[
  'active',
  'duplicate',
  'reversed',
  'ignored',
  'needs_review',
];

class StatementTransactionDetailScreen extends ConsumerStatefulWidget {
  const StatementTransactionDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  ConsumerState<StatementTransactionDetailScreen> createState() => _StatementTransactionDetailScreenState();
}

class _StatementTransactionDetailScreenState extends ConsumerState<StatementTransactionDetailScreen> {
  TextEditingController? _cleanDesc;
  TextEditingController? _notes;
  String _txnType = 'other';
  String _status = 'active';
  String? _categoryId;
  bool _saving = false;
  bool _bound = false;

  @override
  void dispose() {
    _cleanDesc?.dispose();
    _notes?.dispose();
    super.dispose();
  }

  void _bindOnce(StatementTransactionDetailBundle bundle) {
    if (_bound) return;
    _bound = true;
    final txn = bundle.txn;
    final meta = txn['metadata'];
    final m = meta is Map ? Map<String, dynamic>.from(meta) : <String, dynamic>{};
    _cleanDesc = TextEditingController(text: (txn['description_clean'] as String?) ?? '');
    _notes = TextEditingController(text: m['notes']?.toString() ?? '');
    _txnType = (txn['txn_type'] as String?) ?? 'other';
    if (!_kTxnTypes.contains(_txnType)) _txnType = 'other';
    _status = (txn['status'] as String?) ?? 'active';
    if (!_kStatuses.contains(_status)) _status = 'active';
    final cid = txn['category_id'] as String?;
    final catIds = bundle.categories.map((c) => c['id'] as String?).whereType<String>().toSet();
    _categoryId = cid != null && catIds.contains(cid) ? cid : null;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await StatementRepository.updateStatementTransaction(
        widget.transactionId,
        txnType: _txnType,
        status: _status,
        categoryId: _categoryId,
        descriptionClean: _cleanDesc?.text ?? '',
        notes: _notes?.text ?? '',
      );
      if (!mounted) return;
      ref.invalidate(statementTransactionDetailProvider(widget.transactionId));
      ref.invalidate(statementTransactionsProvider);
      ref.invalidate(goatLensWeekDebitSpendProvider);
      ref.invalidate(goatForecastProvider);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR';
    final async = ref.watch(statementTransactionDetailProvider(widget.transactionId));

    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Statement line'),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
          error: (e, _) => Center(child: Text('$e', style: TextStyle(color: GoatTokens.textMuted))),
          data: (bundle) {
            if (bundle == null) {
              return Center(child: Text('Not found.', style: TextStyle(color: GoatTokens.textMuted)));
            }
            _bindOnce(bundle);
            final clean = _cleanDesc!;
            final notes = _notes!;
            final t = bundle.txn;
            final amt = (t['amount'] as num?)?.toDouble() ?? 0;
            final dir = t['direction'] as String? ?? 'debit';
            final meta = t['metadata'] is Map ? Map<String, dynamic>.from(t['metadata'] as Map) : <String, dynamic>{};
            final extraMeta = Map<String, dynamic>.from(meta)..remove('notes')..remove('linked');

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                GoatPremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Imported', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text(
                        t['description_raw'] as String? ?? '',
                        style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${dir == 'debit' ? '−' : '+'}${AppCurrency.format(amt, currency)} · ${t['txn_date']}',
                        style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w700),
                      ),
                      if (extraMeta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            extraMeta.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                            style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.35),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Edit', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: clean,
                  decoration: const InputDecoration(
                    labelText: 'Clean description (optional)',
                    border: OutlineInputBorder(),
                  ),
                  style: TextStyle(color: GoatTokens.textPrimary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes (stored in metadata)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  style: TextStyle(color: GoatTokens.textPrimary),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _txnType,
                  decoration: const InputDecoration(labelText: 'Transaction type', border: OutlineInputBorder()),
                  dropdownColor: GoatTokens.surface,
                  style: TextStyle(color: GoatTokens.textPrimary),
                  items: _kTxnTypes
                      .map((e) => DropdownMenuItem(value: e, child: Text(e, style: TextStyle(color: GoatTokens.textPrimary))))
                      .toList(),
                  onChanged: (v) => setState(() => _txnType = v ?? 'other'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                  dropdownColor: GoatTokens.surface,
                  style: TextStyle(color: GoatTokens.textPrimary),
                  items: _kStatuses
                      .map((e) => DropdownMenuItem(value: e, child: Text(e, style: TextStyle(color: GoatTokens.textPrimary))))
                      .toList(),
                  onChanged: (v) => setState(() => _status = v ?? 'active'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _categoryId,
                  decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                  dropdownColor: GoatTokens.surface,
                  style: TextStyle(color: GoatTokens.textPrimary),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('None')),
                    ...bundle.categories.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c['id'] as String?,
                        child: Text(c['name'] as String? ?? '', style: TextStyle(color: GoatTokens.textPrimary)),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                if (bundle.links.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Linked documents', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ...bundle.links.map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GoatPremiumCard(
                        accentBorder: false,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Match ${l['match_type']} · score ${l['score']}',
                              style: TextStyle(color: GoatTokens.gold, fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            OutlinedButton(
                              onPressed: () {
                                final docId = l['document_id'] as String?;
                                if (docId == null) return;
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(builder: (_) => DocumentDetailScreen(documentId: docId)),
                                );
                              },
                              child: const Text('Open document'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
