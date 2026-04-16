import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/transactions_provider.dart';
import '../../../services/transaction_service.dart';
import '../../documents/screens/document_detail_screen.dart';
import '../../documents/screens/document_edit_screen.dart';

class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  ConsumerState<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends ConsumerState<TransactionDetailScreen> {
  Map<String, dynamic>? _txn;
  List<Map<String, dynamic>> _activityEvents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await TransactionService.fetchTransactionById(widget.transactionId);
    final events = await _fetchActivityEvents();
    if (mounted) setState(() { _txn = data; _activityEvents = events; _loading = false; });
  }

  Future<List<Map<String, dynamic>>> _fetchActivityEvents() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return [];
      final res = await Supabase.instance.client
          .from('activity_events')
          .select()
          .eq('entity_type', 'transaction')
          .eq('entity_id', widget.transactionId)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
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
        actions: [
          TextButton(
            onPressed: _handleEdit,
            child: const Text(
              'Edit',
              style: TextStyle(
                color: BillyTheme.emerald600,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
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
    final paymentMethod = txn['payment_method'] as String?;
    final sourceDocId = txn['source_document_id'] as String?;
    final groupId = txn['group_id'] as String?;
    final isVoided = status == 'voided';
    final extractedData = txn['extracted_data'] as Map<String, dynamic>?;
    final invoiceRef = extractedData?['invoice_number'] as String?
        ?? extractedData?['reference'] as String?;

    String formattedDate = date;
    String formattedTime = '';
    try {
      final dt = DateTime.parse(date);
      formattedDate = DateFormat('dd MMMM yyyy').format(dt);
      formattedTime = DateFormat('h:mm a').format(dt);
    } catch (_) {}

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          children: [
            // ── Hero section (no card) ──────────────────
            _buildHeroSection(
              type: type,
              title: title,
              amount: effectiveAmount ?? amount,
              formattedDate: formattedDate,
              formattedTime: formattedTime,
              isVoided: isVoided,
              currency: currency,
              status: status,
            ),

            const SizedBox(height: 24),

            // ── Source Evidence ──────────────────────────
            if (sourceDocId != null && sourceDocId.isNotEmpty)
              _buildSourceEvidenceCard(sourceDocId, invoiceRef),

            // ── Allocations (shared expense) ────────────
            if (effectiveAmount != null && effectiveAmount != amount)
              _buildAllocationsSection(
                totalAmount: amount,
                yourShare: effectiveAmount,
                currency: currency,
                groupId: groupId,
              ),

            // ── Category & Method pills ─────────────────
            _buildInfoPills(
              category: description,
              method: paymentMethod,
              sourceType: sourceType,
            ),

            const SizedBox(height: 16),

            // ── Activity Trail ──────────────────────────
            if (_activityEvents.isNotEmpty)
              _buildActivityTrail(),

            const SizedBox(height: 24),

            // ── Void Transaction ────────────────────────
            if (!isVoided)
              _buildVoidButton(title, amount, currency),
          ],
        ),
      ),
    );
  }

  // ── Hero section ────────────────────────────────────────

  Widget _buildHeroSection({
    required String type,
    required String title,
    required double amount,
    required String formattedDate,
    required String formattedTime,
    required bool isVoided,
    required String? currency,
    required String status,
  }) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: _typeColor(type),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Icon(_typeIcon(type), size: 28, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: isVoided ? BillyTheme.gray400 : BillyTheme.gray800,
            decoration: isVoided ? TextDecoration.lineThrough : null,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          formattedTime.isNotEmpty ? '$formattedDate · $formattedTime' : formattedDate,
          style: const TextStyle(fontSize: 13, color: BillyTheme.gray500),
        ),
        const SizedBox(height: 12),
        Text(
          AppCurrency.format(amount, currency),
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: isVoided ? BillyTheme.gray400 : BillyTheme.gray800,
            decoration: isVoided ? TextDecoration.lineThrough : null,
          ),
        ),
        if (isVoided) ...[
          const SizedBox(height: 10),
          _StatusBadge(status: status),
        ],
      ],
    );
  }

  // ── Source Evidence card ─────────────────────────────────

  Widget _buildSourceEvidenceCard(String sourceDocId, String? invoiceRef) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BillyTheme.gray100),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: BillyTheme.emerald50,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.description_outlined, size: 24, color: BillyTheme.emerald600),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Source Evidence',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    invoiceRef != null ? 'Ref: $invoiceRef' : 'Linked document',
                    style: const TextStyle(fontSize: 12, color: BillyTheme.gray500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => DocumentDetailScreen(documentId: sourceDocId)),
              ),
              style: TextButton.styleFrom(
                backgroundColor: BillyTheme.emerald600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('View Full', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Allocations section ─────────────────────────────────

  Widget _buildAllocationsSection({
    required double totalAmount,
    required double yourShare,
    required String? currency,
    String? groupId,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Allocations',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: BillyTheme.emerald100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'SHARED',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: BillyTheme.emerald700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: BillyTheme.gray50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: BillyTheme.gray100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL AMOUNT',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: BillyTheme.gray500),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppCurrency.format(totalAmount, currency),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: BillyTheme.gray800),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [BillyTheme.emerald600, BillyTheme.emerald500],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR SHARE',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppCurrency.format(yourShare, currency),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Category & Method info pills ────────────────────────

  Widget _buildInfoPills({
    String? category,
    String? method,
    required String sourceType,
  }) {
    final categoryLabel = category ?? _typeLabel(_txn?['type'] as String? ?? '');
    final methodLabel = method ?? _sourceLabel(sourceType);

    return Row(
      children: [
        Expanded(
          child: _InfoPillCard(
            icon: Icons.category_outlined,
            label: 'CATEGORY',
            value: categoryLabel,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InfoPillCard(
            icon: Icons.credit_card_outlined,
            label: 'METHOD',
            value: methodLabel,
          ),
        ),
      ],
    );
  }

  // ── Activity Trail ──────────────────────────────────────

  Widget _buildActivityTrail() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Activity Trail',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: BillyTheme.gray100),
            ),
            child: Column(
              children: List.generate(_activityEvents.length, (i) {
                final event = _activityEvents[i];
                final isLast = i == _activityEvents.length - 1;
                return _buildTimelineItem(event, isLast);
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> event, bool isLast) {
    final summary = event['summary'] as String? ?? '';
    final createdAt = event['created_at'] as String? ?? '';
    final eventType = event['event_type'] as String? ?? '';

    String timeLabel = '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      timeLabel = DateFormat('dd MMM · h:mm a').format(dt);
    } catch (_) {}

    final displaySummary = _eventDisplayName(eventType, summary);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: BillyTheme.emerald500,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: BillyTheme.emerald100,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 4 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displaySummary,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeLabel,
                    style: const TextStyle(fontSize: 12, color: BillyTheme.gray400),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _eventDisplayName(String eventType, String fallback) {
    const map = {
      'transaction_created': 'Transaction Created',
      'transaction_updated': 'Transaction Updated',
      'transaction_voided': 'Transaction Voided',
      'transaction_disputed': 'Transaction Disputed',
      'document_scanned': 'Document Scanned',
      'group_expense_created': 'Shared with Group',
      'settlement_created': 'Settlement Created',
    };
    return map[eventType] ?? fallback;
  }

  // ── Void button ─────────────────────────────────────────

  Widget _buildVoidButton(String title, double amount, String? currency) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _confirmVoid(title, amount, currency),
        icon: const Icon(Icons.warning_amber_rounded, size: 20),
        label: const Text('Void Transaction'),
        style: OutlinedButton.styleFrom(
          foregroundColor: BillyTheme.red500,
          side: const BorderSide(color: BillyTheme.red500, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ── Existing logic (preserved) ──────────────────────────

  void _handleEdit() {
    if (_txn == null) return;
    final sourceDocId = _txn!['source_document_id'] as String?;
    if (sourceDocId != null && sourceDocId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => DocumentEditScreen(documentId: sourceDocId),
        ),
      ).then((edited) {
        if (edited == true) _load();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No linked document to edit'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
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

// ── Private widgets ───────────────────────────────────────

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

class _InfoPillCard extends StatelessWidget {
  const _InfoPillCard({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: BillyTheme.emerald600),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: BillyTheme.gray400),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
