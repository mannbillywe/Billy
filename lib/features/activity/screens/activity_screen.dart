import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/activity_feed_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../transactions/screens/transaction_detail_screen.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  String _searchQuery = '';
  String _activeFilter = 'all';

  static const _filters = [
    ('all', 'All'),
    ('expenses', 'Expenses'),
    ('income', 'Income'),
    ('shared', 'Shared'),
    ('settlements', 'Settlements'),
  ];

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> events) {
    var filtered = events;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((e) {
        final summary = (e['summary'] as String? ?? '').toLowerCase();
        final vendor = (e['vendor_name'] as String? ?? '').toLowerCase();
        final category = (e['category'] as String? ?? '').toLowerCase();
        return summary.contains(q) || vendor.contains(q) || category.contains(q);
      }).toList();
    }

    if (_activeFilter != 'all') {
      filtered = filtered.where((e) {
        final type = e['event_type'] as String? ?? '';
        final amount = (e['amount'] as num?)?.toDouble() ?? 0;
        switch (_activeFilter) {
          case 'expenses':
            return type.contains('transaction') && amount < 0;
          case 'income':
            return type.contains('transaction') && amount > 0;
          case 'shared':
            return type.contains('group_expense');
          case 'settlements':
            return type.contains('settlement');
          default:
            return true;
        }
      }).toList();
    }

    return filtered;
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(List<Map<String, dynamic>> events) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final event in events) {
      final createdAt = event['created_at'] as String? ?? '';
      String label;
      try {
        final dt = DateTime.parse(createdAt);
        final date = DateTime(dt.year, dt.month, dt.day);
        if (date == today) {
          label = 'TODAY, ${DateFormat('MMM d').format(dt).toUpperCase()}';
        } else if (date == yesterday) {
          label = 'YESTERDAY, ${DateFormat('MMM d').format(dt).toUpperCase()}';
        } else {
          label = DateFormat('EEE, MMM d').format(dt).toUpperCase();
        }
      } catch (_) {
        label = 'UNKNOWN DATE';
      }
      grouped.putIfAbsent(label, () => []).add(event);
    }
    return grouped;
  }

  double _totalSpending(List<Map<String, dynamic>> events) {
    double total = 0;
    for (final e in events) {
      final amount = (e['amount'] as num?)?.toDouble() ?? 0;
      if (amount < 0) total += amount.abs();
    }
    return total;
  }

  double _sharedTotal(List<Map<String, dynamic>> events) {
    double total = 0;
    for (final e in events) {
      final type = e['event_type'] as String? ?? '';
      final amount = (e['amount'] as num?)?.toDouble() ?? 0;
      if (type.contains('group_expense') && amount < 0) total += amount.abs();
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(activityFeedProvider);
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String?;

    return RefreshIndicator(
      color: BillyTheme.emerald600,
      onRefresh: () => ref.read(activityFeedProvider.notifier).refresh(),
      child: feedAsync.when(
        data: (events) {
          final filtered = _applyFilters(events);
          return _buildBody(filtered, events, currency);
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: BillyTheme.emerald600),
        ),
        error: (e, _) => _buildError(),
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> filtered, List<Map<String, dynamic>> allEvents, String? currency) {
    final grouped = _groupByDate(filtered);
    final sliverChildren = <Widget>[];

    sliverChildren.add(SliverToBoxAdapter(child: _buildSearchBar()));
    sliverChildren.add(SliverToBoxAdapter(child: _buildFilterChips()));

    if (filtered.isEmpty) {
      sliverChildren.add(SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      ));
    } else {
      for (final entry in grouped.entries) {
        sliverChildren.add(SliverToBoxAdapter(
          child: _buildDateHeader(entry.key),
        ));
        sliverChildren.add(SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _TransactionCard(event: entry.value[index], currency: currency),
            childCount: entry.value.length,
          ),
        ));
      }

      sliverChildren.add(SliverToBoxAdapter(
        child: _buildSummaryCard(allEvents, currency),
      ));
    }

    sliverChildren.add(const SliverToBoxAdapter(child: SizedBox(height: 120)));

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: sliverChildren,
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: BillyTheme.gray50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BillyTheme.gray100),
        ),
        child: TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(fontSize: 15, color: BillyTheme.gray800),
          decoration: InputDecoration(
            hintText: "Search Billy's history...",
            hintStyle: const TextStyle(fontSize: 15, color: BillyTheme.gray400, fontWeight: FontWeight.w400),
            prefixIcon: const Icon(Icons.search_rounded, color: BillyTheme.gray400, size: 22),
            suffixIcon: IconButton(
              icon: const Icon(Icons.tune_rounded, color: BillyTheme.gray500, size: 20),
              onPressed: _showAdvancedFilters,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  void _showAdvancedFilters() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Filter Activity', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
              const SizedBox(height: 4),
              const Text('Choose which events to display', style: TextStyle(fontSize: 13, color: BillyTheme.gray500)),
              const SizedBox(height: 16),
              ..._filters.map((f) {
                final (key, label) = f;
                final isActive = _activeFilter == key;
                return ListTile(
                  leading: Icon(
                    _filterIcon(key),
                    color: isActive ? BillyTheme.emerald600 : BillyTheme.gray400,
                  ),
                  title: Text(
                    label,
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? BillyTheme.emerald700 : BillyTheme.gray800,
                    ),
                  ),
                  trailing: isActive ? const Icon(Icons.check_rounded, color: BillyTheme.emerald600) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    setState(() => _activeFilter = key);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 8),
              if (_searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _searchQuery = '');
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    label: const Text('Clear search'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _filterIcon(String key) {
    switch (key) {
      case 'expenses': return Icons.shopping_bag_outlined;
      case 'income': return Icons.account_balance_wallet_outlined;
      case 'shared': return Icons.group_outlined;
      case 'settlements': return Icons.payments_outlined;
      default: return Icons.list_rounded;
    }
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (key, label) = _filters[index];
          final isActive = _activeFilter == key;
          return GestureDetector(
            onTap: () => setState(() => _activeFilter = key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? BillyTheme.emerald600 : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? BillyTheme.emerald600 : BillyTheme.gray200,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : BillyTheme.gray700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDateHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
          color: BillyTheme.gray400,
        ),
      ),
    );
  }

  Widget _buildSummaryCard(List<Map<String, dynamic>> events, String? currency) {
    final total = _totalSpending(events);
    final shared = _sharedTotal(events);
    final personal = total - shared;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [BillyTheme.emerald700, BillyTheme.emerald600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MONTHLY SPENDING FLOW',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppCurrency.format(total, currency),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Total spending across ${events.length} transactions',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _summaryBreakdownItem(
                    'Shared',
                    shared,
                    Icons.group_outlined,
                    currency,
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                Expanded(
                  child: _summaryBreakdownItem(
                    'Personal',
                    personal,
                    Icons.person_outline_rounded,
                    currency,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBreakdownItem(String label, double amount, IconData icon, String? currency) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          AppCurrency.format(amount, currency),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: BillyTheme.gray100,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.timeline_outlined, size: 36, color: BillyTheme.gray400),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'No matching results' : 'No activity yet',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BillyTheme.gray600),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different search term or filter'
                : 'Scan a receipt or add an expense\nto see your activity here',
            style: const TextStyle(fontSize: 14, color: BillyTheme.gray400),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
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

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.event, this.currency});
  final Map<String, dynamic> event;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final eventType = event['event_type'] as String? ?? '';
    final summary = event['summary'] as String? ?? '';
    final vendor = event['vendor_name'] as String? ?? summary;
    final category = event['category'] as String? ?? _eventTypeLabel(eventType);
    final createdAt = event['created_at'] as String? ?? '';
    final amount = (event['amount'] as num?)?.toDouble();
    final shareAmount = (event['share_amount'] as num?)?.toDouble();
    final transactionId = event['transaction_id'] as String?;
    final hasTxn = transactionId != null && transactionId.isNotEmpty;
    final isShared = eventType.contains('group_expense');

    String formattedTime = '';
    try {
      final dt = DateTime.parse(createdAt);
      formattedTime = DateFormat('h:mm a').format(dt);
    } catch (_) {}

    final icon = _iconForEvent(eventType);
    final isIncome = amount != null && amount > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BillyTheme.gray100),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: hasTxn
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => TransactionDetailScreen(transactionId: transactionId),
                      ),
                    )
                : null,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: BillyTheme.emerald50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 22, color: BillyTheme.emerald600),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vendor,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: BillyTheme.gray800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$category · $formattedTime',
                          style: const TextStyle(fontSize: 12, color: BillyTheme.gray500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (amount != null)
                        Text(
                          isIncome
                              ? '+${AppCurrency.format(amount, currency)}'
                              : '-${AppCurrency.format(amount.abs(), currency)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isIncome ? BillyTheme.emerald600 : BillyTheme.gray800,
                          ),
                        ),
                      if (isShared && shareAmount != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: BillyTheme.emerald50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'YOUR SHARE: ${AppCurrency.format(shareAmount.abs(), currency)}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: BillyTheme.emerald700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
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
}
