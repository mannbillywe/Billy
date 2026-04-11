import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/activity_feed_provider.dart';
import '../../transactions/screens/transaction_detail_screen.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(activityFeedProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(activityFeedProvider.notifier).refresh(),
      child: feedAsync.when(
        data: (events) => events.isEmpty
            ? _buildEmpty()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                itemCount: events.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) return _buildHeader();
                  return _EventCard(event: events[index - 1]);
                },
              ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: BillyTheme.emerald600),
        ),
        error: (e, _) => _buildError(ref),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('Activity', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
          SizedBox(height: 4),
          Text('Everything that happened with your money', style: TextStyle(fontSize: 14, color: BillyTheme.gray500)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      children: [
        _buildHeader(),
        const SizedBox(height: 40),
        Center(
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: BillyTheme.gray100, borderRadius: BorderRadius.circular(22)),
                child: const Icon(Icons.timeline_outlined, size: 36, color: BillyTheme.gray400),
              ),
              const SizedBox(height: 16),
              const Text('No activity yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BillyTheme.gray600)),
              const SizedBox(height: 8),
              const Text(
                'Scan a receipt or add an expense\nto see your activity here',
                style: TextStyle(fontSize: 14, color: BillyTheme.gray400),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildError(WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.cloud_off_outlined, size: 32, color: BillyTheme.red500),
          ),
          const SizedBox(height: 16),
          const Text('Failed to load activity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray600)),
          const SizedBox(height: 8),
          const Text('Check your connection and try again', style: TextStyle(fontSize: 13, color: BillyTheme.gray400)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => ref.read(activityFeedProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: BillyTheme.emerald600,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final eventType = event['event_type'] as String? ?? '';
    final summary = event['summary'] as String? ?? '';
    final createdAt = event['created_at'] as String? ?? '';
    final transactionId = event['transaction_id'] as String?;
    final hasTxn = transactionId != null && transactionId.isNotEmpty;

    String formattedTime = '';
    try {
      final dt = DateTime.parse(createdAt);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) {
        formattedTime = 'Just now';
      } else if (diff.inMinutes < 60) {
        formattedTime = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        formattedTime = '${diff.inHours}h ago';
      } else if (diff.inDays < 7) {
        formattedTime = '${diff.inDays}d ago';
      } else {
        formattedTime = DateFormat('dd MMM').format(dt);
      }
    } catch (_) {}

    final icon = _iconForEvent(eventType);
    final color = _colorForEvent(eventType);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: hasTxn
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => TransactionDetailScreen(transactionId: transactionId),
                    ),
                  )
              : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(formattedTime, style: const TextStyle(fontSize: 12, color: BillyTheme.gray400)),
                          if (hasTxn) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: BillyTheme.gray100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _eventTypeLabel(eventType),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: BillyTheme.gray500),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (hasTxn)
                  const Icon(Icons.chevron_right_rounded, color: BillyTheme.gray300, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _eventTypeLabel(String type) {
    if (type.contains('transaction')) return 'Transaction';
    if (type.contains('group_expense')) return 'Group';
    if (type.contains('settlement')) return 'Settlement';
    if (type.contains('lend') || type.contains('borrow')) return 'IOU';
    if (type.contains('budget')) return 'Budget';
    if (type.contains('recurring')) return 'Recurring';
    if (type.contains('dispute')) return 'Dispute';
    if (type.contains('document')) return 'Scan';
    return 'Event';
  }

  IconData _iconForEvent(String type) {
    switch (type) {
      case 'transaction_created': return Icons.add_circle_outline;
      case 'transaction_updated': return Icons.edit_outlined;
      case 'transaction_voided': return Icons.remove_circle_outline;
      case 'group_expense_created': return Icons.group_add_outlined;
      case 'settlement_created': return Icons.payments_outlined;
      case 'settlement_confirmed': return Icons.check_circle_outline;
      case 'settlement_rejected': return Icons.cancel_outlined;
      case 'lend_created': case 'borrow_created': return Icons.swap_horiz;
      case 'dispute_opened': return Icons.warning_amber_outlined;
      case 'dispute_resolved': return Icons.gavel_outlined;
      case 'budget_exceeded': return Icons.trending_up;
      case 'recurring_due': return Icons.event_outlined;
      case 'document_scanned': return Icons.document_scanner_outlined;
      default: return Icons.receipt_long_outlined;
    }
  }

  Color _colorForEvent(String type) {
    if (type.contains('dispute') || type.contains('rejected') || type.contains('voided') || type.contains('exceeded')) {
      return BillyTheme.red500;
    }
    if (type.contains('settlement') || type.contains('confirmed') || type.contains('resolved')) {
      return BillyTheme.emerald600;
    }
    if (type.contains('group')) return BillyTheme.blue400;
    if (type.contains('lend') || type.contains('borrow')) return const Color(0xFFD97706);
    return BillyTheme.gray600;
  }
}
