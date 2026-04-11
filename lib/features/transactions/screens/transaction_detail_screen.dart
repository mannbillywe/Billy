import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/transactions_provider.dart';
import '../../../services/transaction_service.dart';
import '../../documents/screens/document_detail_screen.dart';

class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  ConsumerState<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends ConsumerState<TransactionDetailScreen> {
  Map<String, dynamic>? _txn;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await TransactionService.fetchTransactionById(widget.transactionId);
    if (mounted) setState(() { _txn = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('Transaction'),
        backgroundColor: BillyTheme.scaffoldBg,
        foregroundColor: BillyTheme.gray800,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: BillyTheme.emerald600))
          : _txn == null
              ? _buildNotFound()
              : _buildBody(currency),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 56, color: BillyTheme.gray300),
          const SizedBox(height: 12),
          const Text('Transaction not found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray500)),
          const SizedBox(height: 16),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Go back')),
        ],
      ),
    );
  }

  Widget _buildBody(String? currency) {
    final txn = _txn!;
    final type = txn['type'] as String? ?? '';
    final title = txn['title'] as String? ?? '';
    final amount = (txn['amount'] as num?)?.toDouble() ?? 0;
    final effectiveAmount = (txn['effective_amount'] as num?)?.toDouble();
    final date = txn['date'] as String? ?? '';
    final status = txn['status'] as String? ?? '';
    final sourceType = txn['source_type'] as String? ?? '';
    final description = txn['description'] as String?;
    final notes = txn['notes'] as String?;
    final sourceDocId = txn['source_document_id'] as String?;
    final isVoided = status == 'voided';

    String formattedDate = date;
    try {
      final dt = DateTime.parse(date);
      formattedDate = DateFormat('EEEE, dd MMMM yyyy').format(dt);
    } catch (_) {}

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          children: [
            // ── Hero card ───────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isVoided
                      ? [BillyTheme.gray100, BillyTheme.gray50]
                      : [BillyTheme.emerald50, BillyTheme.emerald100.withValues(alpha: 0.4)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isVoided ? BillyTheme.gray200 : BillyTheme.emerald100),
              ),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _typeColor(type).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Icon(_typeIcon(type), size: 26, color: _typeColor(type)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isVoided ? BillyTheme.gray400 : BillyTheme.gray800,
                      decoration: isVoided ? TextDecoration.lineThrough : null,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppCurrency.format(effectiveAmount ?? amount, currency),
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: isVoided ? BillyTheme.gray400 : BillyTheme.gray800,
                      decoration: isVoided ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (effectiveAmount != null && effectiveAmount != amount) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Total ${AppCurrency.format(amount, currency)} · Your share',
                      style: const TextStyle(fontSize: 13, color: BillyTheme.gray500),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _StatusBadge(status: status),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Detail rows ─────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: BillyTheme.gray100),
              ),
              child: Column(
                children: [
                  _DetailRow(icon: Icons.category_outlined, label: 'Type', value: _typeLabel(type)),
                  _DetailRow(icon: Icons.calendar_today_outlined, label: 'Date', value: formattedDate),
                  _DetailRow(icon: Icons.source_outlined, label: 'Source', value: _sourceLabel(sourceType)),
                  if (description != null && description.isNotEmpty)
                    _DetailRow(icon: Icons.label_outline, label: 'Category', value: description),
                  if (notes != null && notes.isNotEmpty)
                    _DetailRow(icon: Icons.notes_outlined, label: 'Notes', value: notes, isLast: true),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Actions ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: BillyTheme.gray100),
              ),
              child: Column(
                children: [
                  if (sourceDocId != null && sourceDocId.isNotEmpty)
                    _ActionTile(
                      icon: Icons.receipt_long_outlined,
                      iconColor: BillyTheme.emerald600,
                      label: 'View source document',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => DocumentDetailScreen(documentId: sourceDocId)),
                      ),
                    ),
                  if (!isVoided)
                    _ActionTile(
                      icon: Icons.remove_circle_outline,
                      iconColor: BillyTheme.red500,
                      label: 'Void transaction',
                      isDestructive: true,
                      onTap: () => _confirmVoid(title, amount, currency),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmVoid(String title, double amount, String? currency) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.warning_amber_rounded, size: 40, color: BillyTheme.red500),
        title: const Text('Void this transaction?'),
        content: Text(
          'This will mark "$title" (${AppCurrency.format(amount, currency)}) as voided. This action cannot be undone.',
          style: const TextStyle(color: BillyTheme.gray600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: BillyTheme.gray500)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: BillyTheme.red500),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(transactionsProvider.notifier).voidTransaction(widget.transactionId);
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Transaction voided'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: BillyTheme.red500, behavior: SnackBarBehavior.floating),
          );
        }
      }
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'expense': return Icons.shopping_bag_outlined;
      case 'income': return Icons.account_balance_wallet_outlined;
      case 'lend': return Icons.arrow_upward_rounded;
      case 'borrow': return Icons.arrow_downward_rounded;
      case 'settlement_out': return Icons.payments_outlined;
      case 'settlement_in': return Icons.payments_outlined;
      case 'transfer': return Icons.swap_horiz_rounded;
      case 'refund': return Icons.replay_rounded;
      case 'recurring': return Icons.autorenew_rounded;
      default: return Icons.receipt_long_outlined;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'expense': return BillyTheme.emerald600;
      case 'income': return BillyTheme.blue400;
      case 'lend': return const Color(0xFFD97706);
      case 'borrow': return BillyTheme.red500;
      case 'settlement_out': case 'settlement_in': return BillyTheme.emerald600;
      case 'refund': return BillyTheme.blue400;
      default: return BillyTheme.gray600;
    }
  }

  String _typeLabel(String type) {
    const map = {
      'expense': 'Expense', 'income': 'Income', 'lend': 'Lent', 'borrow': 'Borrowed',
      'settlement_out': 'Settlement (paid)', 'settlement_in': 'Settlement (received)',
      'transfer': 'Transfer', 'refund': 'Refund', 'recurring': 'Recurring',
    };
    return map[type] ?? type;
  }

  String _sourceLabel(String source) {
    const map = {
      'scan': 'Scanned document', 'manual': 'Manual entry', 'statement': 'Statement import',
      'group_split': 'Group expense', 'settlement': 'Settlement', 'recurring': 'Recurring bill',
    };
    return map[source] ?? source;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      'confirmed' => (const Color(0xFFD1FAE5), BillyTheme.emerald700),
      'draft' => (BillyTheme.gray200, BillyTheme.gray600),
      'pending' => (const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      'voided' => (const Color(0xFFFEE2E2), BillyTheme.red500),
      'disputed' => (const Color(0xFFFEE2E2), BillyTheme.red400),
      _ => (BillyTheme.gray200, BillyTheme.gray600),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: fg)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value, this.isLast = false});
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: BillyTheme.gray400),
              const SizedBox(width: 10),
              SizedBox(
                width: 80,
                child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillyTheme.gray500)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray800)),
              ),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: BillyTheme.gray100),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.iconColor, required this.label, required this.onTap, this.isDestructive = false});
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDestructive ? BillyTheme.red500 : BillyTheme.gray800)),
      trailing: Icon(Icons.chevron_right_rounded, color: BillyTheme.gray300, size: 20),
    );
  }
}
