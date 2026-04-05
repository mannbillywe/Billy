import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../group_balance.dart';
import '../../../providers/group_expenses_provider.dart';
import '../../../providers/group_settlements_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../services/supabase_service.dart';

class GroupExpensesScreen extends ConsumerWidget {
  const GroupExpensesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.members,
  });

  final String groupId;
  final String groupName;
  final List<Map<String, dynamic>> members;

  static String _memberLabel(Map<String, dynamic> m) {
    final prof = m['member_profile'] as Map<String, dynamic>?;
    final dn = prof?['display_name'] as String?;
    if (dn != null && dn.trim().isNotEmpty) return dn.trim();
    return 'Member';
  }

  static String? _memberUserId(Map<String, dynamic> m) => m['user_id'] as String?;

  void _invalidateLedger(WidgetRef ref) {
    ref.invalidate(groupExpensesProvider(groupId));
    ref.invalidate(groupSettlementsProvider(groupId));
  }

  String _labelForUid(String uid) {
    for (final m in members) {
      if (_memberUserId(m) == uid) return _memberLabel(m);
    }
    return 'Member';
  }

  Future<void> _showSettlementSheet(BuildContext parentContext, WidgetRef ref) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || members.length < 2) return;

    final others = members.where((m) => _memberUserId(m) != null && _memberUserId(m) != uid).toList();
    if (others.isEmpty) return;

    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String payeeId = _memberUserId(others.first)!;
    final profile = ref.read(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;

    await showModalBottomSheet<void>(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Record payment',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
                ),
                const SizedBox(height: 8),
                Text(
                  'You paid someone back in this group. Balances update for everyone.',
                  style: TextStyle(fontSize: 13, color: BillyTheme.gray500),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(payeeId),
                  value: payeeId,
                  decoration: const InputDecoration(labelText: 'Paid to', border: OutlineInputBorder()),
                  items: [
                    for (final m in others)
                      DropdownMenuItem(
                        value: _memberUserId(m)!,
                        child: Text(_memberLabel(m)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setSheet(() => payeeId = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount (${currency ?? 'USD'})',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final amount = double.tryParse(amountCtrl.text.trim());
                    if (amount == null || amount <= 0) return;
                    Navigator.pop(ctx);
                    try {
                      await SupabaseService.insertGroupSettlement(
                        groupId: groupId,
                        payeeUserId: payeeId,
                        amount: amount,
                        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                      );
                      _invalidateLedger(ref);
                    } catch (e) {
                      if (parentContext.mounted) {
                        ScaffoldMessenger.of(parentContext).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: BillyTheme.emerald600, padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext parentContext, WidgetRef ref) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || members.isEmpty) return;

    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final memberIds = members.map(_memberUserId).whereType<String>().toList();
    final chosen = {...memberIds};
    String paidBy = memberIds.contains(uid) ? uid : memberIds.first;
    final profile = ref.read(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;

    await showModalBottomSheet<void>(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Add group expense', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Total (${currency ?? 'USD'})',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(paidBy),
                  value: paidBy,
                  decoration: const InputDecoration(labelText: 'Paid by', border: OutlineInputBorder()),
                  items: [
                    for (final m in members)
                      if (_memberUserId(m) != null)
                        DropdownMenuItem(
                          value: _memberUserId(m)!,
                          child: Text(_memberLabel(m)),
                        ),
                  ],
                  onChanged: (v) {
                    if (v != null) setSheet(() => paidBy = v);
                  },
                ),
                const SizedBox(height: 16),
                Text('Split between', style: TextStyle(fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
                const SizedBox(height: 8),
                ...members.map((m) {
                  final id = _memberUserId(m);
                  if (id == null) return const SizedBox.shrink();
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_memberLabel(m)),
                    value: chosen.contains(id),
                    onChanged: (on) {
                      setSheet(() {
                        if (on == true) {
                          chosen.add(id);
                        } else {
                          chosen.remove(id);
                        }
                        if (!chosen.contains(paidBy) && chosen.isNotEmpty) {
                          paidBy = chosen.first;
                        }
                      });
                    },
                  );
                }),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    final amount = double.tryParse(amountCtrl.text.trim());
                    final splitIds = chosen.toList()..sort();
                    if (amount == null || amount <= 0 || splitIds.isEmpty) return;
                    if (!splitIds.contains(paidBy)) return;
                    final shares = equalSharesForUsers(splitIds, amount);
                    Navigator.pop(ctx);
                    try {
                      await SupabaseService.createGroupExpense(
                        groupId: groupId,
                        title: title.isEmpty ? 'Expense' : title,
                        amount: amount,
                        paidByUserId: paidBy,
                        expenseDate: DateTime.now(),
                        shares: shares,
                      );
                      _invalidateLedger(ref);
                    } catch (e) {
                      if (parentContext.mounted) {
                        ScaffoldMessenger.of(parentContext).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: BillyTheme.emerald600, padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(groupExpensesProvider(groupId));
    final settlementsAsync = ref.watch(groupSettlementsProvider(groupId));
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;
    final myUid = Supabase.instance.client.auth.currentUser?.id;
    final memberIds = members.map(_memberUserId).whereType<String>().toList();

    return Scaffold(
      backgroundColor: BillyTheme.gray50,
      appBar: AppBar(
        title: Text(groupName),
        backgroundColor: Colors.white,
        foregroundColor: BillyTheme.gray800,
        elevation: 0,
        actions: [
          if (members.length >= 2)
            IconButton(
              tooltip: 'Record payment',
              icon: const Icon(Icons.payments_outlined),
              onPressed: () => _showSettlementSheet(context, ref),
            ),
        ],
      ),
      floatingActionButton: members.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddSheet(context, ref),
              backgroundColor: BillyTheme.emerald600,
              icon: const Icon(Icons.add),
              label: const Text('Expense'),
            ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
        data: (rows) {
          return settlementsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
            data: (settlements) {
              final expenseNet = expenseNetFromRows(rows);
              final combined = applySettlements(expenseNet, settlements);
              final net = netForMembers(combined, memberIds);
              final sortedUids = List<String>.from(memberIds)
                ..sort((a, b) => _labelForUid(a).toLowerCase().compareTo(_labelForUid(b).toLowerCase()));

              Future<void> onRefresh() async {
                ref.invalidate(groupExpensesProvider(groupId));
                ref.invalidate(groupSettlementsProvider(groupId));
                await Future.wait([
                  ref.read(groupExpensesProvider(groupId).future),
                  ref.read(groupSettlementsProvider(groupId).future),
                ]);
              }

              return RefreshIndicator(
                onRefresh: onRefresh,
                color: BillyTheme.emerald600,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Balances', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: BillyTheme.gray800)),
                            const SizedBox(height: 4),
                            Text(
                              'Positive = owed to them · Negative = they owe',
                              style: TextStyle(fontSize: 12, color: BillyTheme.gray500),
                            ),
                            const SizedBox(height: 10),
                            ...sortedUids.map((id) {
                              final v = net[id] ?? 0;
                              final isZero = v.abs() < 0.005;
                              final color = isZero
                                  ? BillyTheme.gray600
                                  : (v > 0 ? BillyTheme.emerald600 : BillyTheme.red500);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(_labelForUid(id), style: const TextStyle(fontWeight: FontWeight.w600)),
                                        Text(
                                          AppCurrency.format(v, currency),
                                          style: TextStyle(fontWeight: FontWeight.w700, color: color),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    if (settlements.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Recorded payments', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: BillyTheme.gray800)),
                              const SizedBox(height: 8),
                              ...settlements.map((s) {
                                final payer = s['payer_profile'] as Map<String, dynamic>?;
                                final payee = s['payee_profile'] as Map<String, dynamic>?;
                                final pn = payer?['display_name'] as String? ?? 'Someone';
                                final en = payee?['display_name'] as String? ?? 'Someone';
                                final amt = (s['amount'] as num?)?.toDouble() ?? 0;
                                final note = s['note'] as String?;
                                final createdBy = s['created_by'] as String?;
                                final canDelete = myUid != null && createdBy == myUid;
                                final created = s['created_at'] as String?;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    child: ListTile(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(color: BillyTheme.gray100),
                                      ),
                                      title: Text('$pn → $en', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                      subtitle: Text(
                                        [AppCurrency.format(amt, currency), if (note != null && note.isNotEmpty) note, if (created != null) created.split('T').first]
                                            .join(' · '),
                                        style: TextStyle(fontSize: 12, color: BillyTheme.gray500),
                                      ),
                                      trailing: canDelete
                                          ? IconButton(
                                              icon: Icon(Icons.delete_outline, color: BillyTheme.red500),
                                              onPressed: () async {
                                                final ok = await showDialog<bool>(
                                                  context: context,
                                                  builder: (c) => AlertDialog(
                                                    title: const Text('Delete this payment record?'),
                                                    actions: [
                                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                                                    ],
                                                  ),
                                                );
                                                if (ok == true) {
                                                  try {
                                                    await SupabaseService.deleteGroupSettlement(s['id'] as String);
                                                    _invalidateLedger(ref);
                                                  } catch (err) {
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
                                                    }
                                                  }
                                                }
                                              },
                                            )
                                          : null,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text('Expenses', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: BillyTheme.gray800)),
                      ),
                    ),
                    if (rows.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No shared expenses yet.\nTap Expense to add one — split is equal across selected members.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: BillyTheme.gray500),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            childCount: rows.length,
                            (ctx, i) {
                              final e = rows[i];
                              final title = e['title'] as String? ?? 'Expense';
                              final amount = (e['amount'] as num?)?.toDouble() ?? 0;
                              final dateStr = e['expense_date'] as String? ?? '';
                              final payer = e['payer'] as Map<String, dynamic>?;
                              final payerName = payer?['display_name'] as String? ?? 'Someone';
                              final parts = (e['group_expense_participants'] as List?) ?? [];
                              final createdBy = e['created_by'] as String?;
                              final canDelete = myUid != null && createdBy == myUid;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  child: ExpansionTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: BillyTheme.gray100),
                                    ),
                                    collapsedShape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: BillyTheme.gray100),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
                                        if (canDelete)
                                          IconButton(
                                            icon: Icon(Icons.delete_outline, color: BillyTheme.red500),
                                            onPressed: () async {
                                              final ok = await showDialog<bool>(
                                                context: context,
                                                builder: (c) => AlertDialog(
                                                  title: const Text('Delete expense?'),
                                                  actions: [
                                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                                                  ],
                                                ),
                                              );
                                              if (ok == true) {
                                                try {
                                                  await SupabaseService.deleteGroupExpense(e['id'] as String);
                                                  _invalidateLedger(ref);
                                                } catch (err) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
                                                  }
                                                }
                                              }
                                            },
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      '${AppCurrency.format(amount, currency)} · Paid by $payerName · $dateStr',
                                      style: TextStyle(fontSize: 12, color: BillyTheme.gray500),
                                    ),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Shares', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: BillyTheme.gray600)),
                                            const SizedBox(height: 6),
                                            ...parts.map((p) {
                                              final m = p as Map<String, dynamic>;
                                              final prof = m['participant'] as Map<String, dynamic>?;
                                              final nm = prof?['display_name'] as String? ?? 'Member';
                                              final sh = (m['share_amount'] as num?)?.toDouble() ?? 0;
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 4),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Text(nm, style: const TextStyle(fontSize: 13)),
                                                    Text(AppCurrency.format(sh, currency), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                                  ],
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
