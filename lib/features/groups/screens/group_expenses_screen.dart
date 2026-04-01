import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/group_expenses_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../services/supabase_service.dart';

/// Equal split with 2-decimal rounding; remainder goes to the last member.
List<Map<String, dynamic>> _equalShares(List<String> userIds, double total) {
  if (userIds.isEmpty) return [];
  final n = userIds.length;
  double round2(double x) => (x * 100).round() / 100;
  final each = round2(total / n);
  final out = <Map<String, dynamic>>[];
  var allocated = 0.0;
  for (var i = 0; i < n; i++) {
    if (i == n - 1) {
      out.add({'user_id': userIds[i], 'share_amount': round2(total - allocated)});
    } else {
      out.add({'user_id': userIds[i], 'share_amount': each});
      allocated += each;
    }
  }
  return out;
}

class GroupExpensesScreen extends ConsumerWidget {
  const GroupExpensesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.members,
  });

  final String groupId;
  final String groupName;
  /// Rows from `expense_group_members` (with optional `member_profile`).
  final List<Map<String, dynamic>> members;

  static String _memberLabel(Map<String, dynamic> m) {
    final prof = m['member_profile'] as Map<String, dynamic>?;
    final dn = prof?['display_name'] as String?;
    if (dn != null && dn.trim().isNotEmpty) return dn.trim();
    return 'Member';
  }

  static String? _memberUserId(Map<String, dynamic> m) => m['user_id'] as String?;

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
                    final shares = _equalShares(splitIds, amount);
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
                      ref.invalidate(groupExpensesProvider(groupId));
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
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;
    final myUid = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: BillyTheme.gray50,
      appBar: AppBar(
        title: Text(groupName),
        backgroundColor: Colors.white,
        foregroundColor: BillyTheme.gray800,
        elevation: 0,
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
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No shared expenses yet.\nTap Expense to add one — split is equal across selected members.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: BillyTheme.gray500),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final e = rows[i];
              final title = e['title'] as String? ?? 'Expense';
              final amount = (e['amount'] as num?)?.toDouble() ?? 0;
              final dateStr = e['expense_date'] as String? ?? '';
              final payer = e['payer'] as Map<String, dynamic>?;
              final payerName = payer?['display_name'] as String? ?? 'Someone';
              final parts = (e['group_expense_participants'] as List?) ?? [];
              final createdBy = e['created_by'] as String?;
              final canDelete = myUid != null && createdBy == myUid;

              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: ExpansionTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: BillyTheme.gray100)),
                  collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: BillyTheme.gray100)),
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
                                ref.invalidate(groupExpensesProvider(groupId));
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
              );
            },
          );
        },
      ),
    );
  }
}
