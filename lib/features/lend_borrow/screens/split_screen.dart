import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/lend_borrow_provider.dart';
import '../../../providers/splits_provider.dart';

class SplitScreen extends ConsumerStatefulWidget {
  const SplitScreen({super.key});

  @override
  ConsumerState<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends ConsumerState<SplitScreen> {
  String _activeTab = 'collect';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showAddEntryDialog() {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String type = 'lent';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              const Text('Add Transaction', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
              const SizedBox(height: 20),
              Row(
                children: ['lent', 'borrowed'].map((t) {
                  final isActive = type == t;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setSheetState(() => type = t),
                      child: Container(
                        margin: EdgeInsets.only(right: t == 'lent' ? 8 : 0, left: t == 'borrowed' ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isActive ? BillyTheme.emerald50 : BillyTheme.gray50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isActive ? BillyTheme.emerald600 : BillyTheme.gray200),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          t == 'lent' ? 'I Lent' : 'I Borrowed',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isActive ? BillyTheme.emerald700 : BillyTheme.gray500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  hintText: 'Person name',
                  filled: true,
                  fillColor: BillyTheme.gray50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.gray200)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.gray200)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.emerald600)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Amount (\$)',
                  filled: true,
                  fillColor: BillyTheme.gray50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.gray200)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.gray200)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.emerald600)),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () async {
                  final name = nameCtrl.text.trim();
                  final amount = double.tryParse(amountCtrl.text.trim());
                  if (name.isEmpty || amount == null || amount <= 0) return;
                  Navigator.of(ctx).pop();
                  await ref.read(lendBorrowProvider.notifier).addEntry(
                    counterpartyName: name,
                    amount: amount,
                    type: type,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(color: BillyTheme.emerald600, borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: const Text('Add', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lbAsync = ref.watch(lendBorrowProvider);
    final splitsAsync = ref.watch(splitsProvider);
    final entries = lbAsync.valueOrNull ?? [];
    final splits = splitsAsync.valueOrNull ?? [];
    final pending = entries.where((e) => e['status'] == 'pending').toList();

    double collectTotal = 0;
    double payTotal = 0;
    for (final e in pending) {
      final amount = (e['amount'] as num?)?.toDouble() ?? 0;
      if (e['type'] == 'lent') {
        collectTotal += amount;
      } else {
        payTotal += amount;
      }
    }

    final filtered = pending.where((e) {
      final type = e['type'] as String? ?? '';
      if (_activeTab == 'collect') return type == 'lent';
      return type == 'borrowed';
    }).toList();

    final search = _searchCtrl.text.toLowerCase();
    final displayed = search.isEmpty
        ? filtered
        : filtered.where((e) => (e['counterparty_name'] as String? ?? '').toLowerCase().contains(search)).toList();

    return SingleChildScrollView(
      key: const ValueKey('friends'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: BillyTheme.emerald100, shape: BoxShape.circle),
                child: const Icon(Icons.person_outline, size: 20, color: BillyTheme.emerald600),
              ),
              const SizedBox(width: 12),
              const Text('Borrow & Lend Money', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
              const Spacer(),
              _CircleBtn(icon: Icons.settings_outlined),
            ],
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(child: _SummaryCard(
                label: 'To Collect',
                amount: collectTotal,
                isActive: _activeTab == 'collect',
                isCollect: true,
                onTap: () => setState(() => _activeTab = 'collect'),
              )),
              const SizedBox(width: 12),
              Expanded(child: _SummaryCard(
                label: 'To Pay Back',
                amount: payTotal,
                isActive: _activeTab == 'pay',
                isCollect: false,
                onTap: () => setState(() => _activeTab = 'pay'),
              )),
            ],
          ),
          const SizedBox(height: 16),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BillyTheme.gray100),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Name or ID of money lent to / from',
                hintStyle: const TextStyle(fontSize: 14, color: BillyTheme.gray400),
                prefixIcon: const Icon(Icons.search, size: 18, color: BillyTheme.gray400),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),

          ...displayed.map((e) {
            final name = e['counterparty_name'] as String? ?? '';
            final amount = (e['amount'] as num?)?.toDouble() ?? 0;
            final type = e['type'] as String? ?? 'lent';
            final id = e['id'] as String;
            final isLent = type == 'lent';

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Dismissible(
                key: ValueKey(id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(color: BillyTheme.emerald500, borderRadius: BorderRadius.circular(16)),
                  child: const Text('Settle', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                onDismissed: (_) => ref.read(lendBorrowProvider.notifier).settle(id),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: BillyTheme.gray50),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: BillyTheme.emerald100, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BillyTheme.emerald600),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.receipt_outlined, size: 12, color: BillyTheme.gray500),
                                const SizedBox(width: 4),
                                const Text('IRO', style: TextStyle(fontSize: 12, color: BillyTheme.gray500)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '\$${NumberFormat('#,##0.00').format(amount)}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isLent ? BillyTheme.emerald600 : BillyTheme.red500),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => ref.read(lendBorrowProvider.notifier).settle(id),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isLent ? BillyTheme.emerald500 : BillyTheme.red500,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(isLent ? Icons.check : Icons.arrow_upward, size: 18, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          GestureDetector(
            onTap: _showAddEntryDialog,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 18, color: BillyTheme.emerald600),
                  const SizedBox(width: 8),
                  Text('Add Transaction', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.emerald600)),
                ],
              ),
            ),
          ),

          if (splits.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Groups', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
                const Icon(Icons.more_horiz, size: 20, color: BillyTheme.gray400),
              ],
            ),
            const SizedBox(height: 12),
            ...splits.map((s) {
              final title = s['title'] as String? ?? 'Split';
              final total = (s['total_amount'] as num?)?.toDouble() ?? 0;
              final participants = (s['split_participants'] as List?) ?? [];

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: BillyTheme.gray50),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Row(
                    children: [
                      _AvatarStack(count: participants.length),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
                            Text('Splitting with ${participants.length} friends', style: const TextStyle(fontSize: 12, color: BillyTheme.gray500)),
                          ],
                        ),
                      ),
                      Text('\$${total.toInt()} total', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.emerald600)),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 16, color: BillyTheme.gray400),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Icon(icon, size: 20, color: BillyTheme.gray600),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.amount, required this.isActive, required this.isCollect, required this.onTap});
  final String label;
  final double amount;
  final bool isActive;
  final bool isCollect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeGradient = isCollect
        ? [BillyTheme.green400, BillyTheme.emerald600]
        : [BillyTheme.red400, const Color(0xFFEF4444)];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isActive ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: activeGradient) : null,
          color: isActive ? null : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isActive ? null : Border.all(color: BillyTheme.gray100),
          boxShadow: isActive
              ? [BoxShadow(color: (isCollect ? BillyTheme.emerald500 : BillyTheme.red400).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive ? Colors.white.withValues(alpha: 0.8) : BillyTheme.gray500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '\$${NumberFormat('#,##0.00').format(amount)}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.white : BillyTheme.gray600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.count});
  final int count;

  static const _colors = [BillyTheme.emerald100, BillyTheme.blue400, BillyTheme.yellow400];
  static const _textColors = [BillyTheme.emerald700, Colors.white, Color(0xFF92400E)];

  @override
  Widget build(BuildContext context) {
    final shown = count > 3 ? 2 : count;
    final extra = count - shown;

    return SizedBox(
      width: 28.0 * shown + (extra > 0 ? 28 : 0),
      height: 40,
      child: Stack(
        children: [
          for (int i = 0; i < shown; i++)
            Positioned(
              left: i * 20.0,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _colors[i % _colors.length],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  String.fromCharCode(65 + i),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _textColors[i % _textColors.length]),
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown * 20.0,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: BillyTheme.yellow400.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: Text('+$extra', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
              ),
            ),
        ],
      ),
    );
  }
}
