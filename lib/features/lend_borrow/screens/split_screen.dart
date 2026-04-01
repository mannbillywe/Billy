import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../lend_borrow_perspective.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/lend_borrow_provider.dart';
import '../../groups/screens/group_expenses_screen.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/social_provider.dart';

class SplitScreen extends ConsumerStatefulWidget {
  const SplitScreen({super.key});

  @override
  ConsumerState<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends ConsumerState<SplitScreen> {
  String _activeTab = 'collect';
  final _searchCtrl = TextEditingController();
  final _inviteEmailCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _inviteEmailCtrl.dispose();
    super.dispose();
  }

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  Future<void> _showAddEntrySheet(List<Map<String, dynamic>> connections, List<Map<String, dynamic>> groups) async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String type = 'lent';
    String? linkedUserId;
    String? groupId;
    final profile = ref.read(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;

    await showModalBottomSheet<void>(
      context: context,
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
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                const Text('Add transaction', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                const SizedBox(height: 16),
                Row(
                  children: ['lent', 'borrowed'].map((t) {
                    final active = type == t;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: t == 'lent' ? 8 : 0, left: t == 'borrowed' ? 8 : 0),
                        child: GestureDetector(
                          onTap: () => setSheet(() => type = t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: active ? BillyTheme.emerald50 : BillyTheme.gray50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: active ? BillyTheme.emerald600 : BillyTheme.gray200),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              t == 'lent' ? 'I lent' : 'I borrowed',
                              style: TextStyle(fontWeight: FontWeight.w600, color: active ? BillyTheme.emerald700 : BillyTheme.gray500),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                if (connections.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    value: linkedUserId,
                    decoration: const InputDecoration(labelText: 'Link to contact (optional)', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('No linked user')),
                      ...connections.map((c) => DropdownMenuItem<String?>(
                            value: c['other_user_id'] as String,
                            child: Text(c['display_name'] as String),
                          )),
                    ],
                    onChanged: (v) => setSheet(() {
                      linkedUserId = v;
                      if (v != null) {
                        for (final c in connections) {
                          if (c['other_user_id'] == v) {
                            final dn = c['display_name'] as String?;
                            if (dn != null && dn.isNotEmpty) nameCtrl.text = dn;
                            break;
                          }
                        }
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                if (groups.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    value: groupId,
                    decoration: const InputDecoration(labelText: 'Group (optional)', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('No group')),
                      ...groups.map((g) => DropdownMenuItem<String?>(
                            value: g['id'] as String,
                            child: Text(g['name'] as String? ?? 'Group'),
                          )),
                    ],
                    onChanged: (v) => setSheet(() => groupId = v),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Counterparty name',
                    border: OutlineInputBorder(),
                  ),
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
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final normalizedAmount = amountCtrl.text.trim().replaceAll(',', '.');
                    final amount = double.tryParse(normalizedAmount);
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Enter a counterparty name')),
                      );
                      return;
                    }
                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Enter a valid amount greater than zero')),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    try {
                      await ref.read(lendBorrowProvider.notifier).addEntry(
                            counterpartyName: name,
                            amount: amount,
                            type: type,
                            counterpartyUserId: linkedUserId,
                            groupId: groupId,
                          );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Transaction saved'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Could not save: $e'),
                            backgroundColor: BillyTheme.red500,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
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

  Future<void> _createGroupDialog(List<Map<String, dynamic>> connections) async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New group'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: 'Group name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final gid = await ref.read(expenseGroupsNotifierProvider.notifier).createGroup(nameCtrl.text.trim());
      if (!mounted) return;
      if (connections.isNotEmpty) {
        await _pickMembersForGroup(gid, connections);
      }
    }
    nameCtrl.dispose();
  }

  Future<void> _pickMembersForGroup(String groupId, List<Map<String, dynamic>> connections) async {
    final chosen = <String>{};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Add members'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: connections.map((c) {
                final id = c['other_user_id'] as String;
                return CheckboxListTile(
                  title: Text(c['display_name'] as String),
                  value: chosen.contains(id),
                  onChanged: (v) {
                    setDialog(() {
                      if (v == true) {
                        chosen.add(id);
                      } else {
                        chosen.remove(id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                for (final id in chosen) {
                  await ref.read(expenseGroupsNotifierProvider.notifier).addMember(groupId: groupId, memberUserId: id);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    final lbAsync = ref.watch(lendBorrowProvider);
    final invAsync = ref.watch(invitationsNotifierProvider);
    final connAsync = ref.watch(connectionsNotifierProvider);
    final groupsAsync = ref.watch(expenseGroupsNotifierProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;

    final entries = lbAsync.valueOrNull ?? [];
    final invitations = invAsync.valueOrNull ?? [];
    final connections = connAsync.valueOrNull ?? [];
    final groups = groupsAsync.valueOrNull ?? [];

    final pending = entries.where((e) => e['status'] == 'pending').toList();

    double collectTotal = 0;
    double payTotal = 0;
    for (final e in pending) {
      final amount = (e['amount'] as num?)?.toDouble() ?? 0;
      final t = effectiveTypeForViewer(e, uid);
      if (t == 'lent') {
        collectTotal += amount;
      } else {
        payTotal += amount;
      }
    }

    final filtered = pending.where((e) {
      final t = effectiveTypeForViewer(e, uid);
      if (_activeTab == 'collect') return t == 'lent';
      return t == 'borrowed';
    }).toList();

    final q = _searchCtrl.text.toLowerCase();
    final displayed = q.isEmpty
        ? filtered
        : filtered.where((e) => otherPartyDisplayName(e, uid).toLowerCase().contains(q)).toList();

    final outgoing = invitations.where((i) => i['from_user_id'] == uid && i['status'] == 'pending').toList();
    final incoming = invitations.where((i) => i['from_user_id'] != uid && i['status'] == 'pending').toList();

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
                child: const Icon(Icons.people_outline, size: 22, color: BillyTheme.emerald600),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('People & groups', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Invite by email. After they accept, linked transactions are visible to both of you.',
            style: TextStyle(fontSize: 12, color: BillyTheme.gray500),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inviteEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'friend@email.com',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: invAsync.isLoading
                    ? null
                    : () async {
                        final em = _inviteEmailCtrl.text.trim();
                        if (em.isEmpty) return;
                        try {
                          await ref.read(invitationsNotifierProvider.notifier).inviteEmail(em);
                          _inviteEmailCtrl.clear();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitation sent')));
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                          }
                        }
                      },
                style: FilledButton.styleFrom(backgroundColor: BillyTheme.emerald600),
                child: const Text('Invite'),
              ),
            ],
          ),
          if (incoming.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Invitations for you', style: TextStyle(fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
            const SizedBox(height: 8),
            ...incoming.map((i) => _InvitationTile(
                  title: 'Contact invitation',
                  subtitle: i['to_email'] as String? ?? '',
                  isIncoming: true,
                  onAccept: () => ref.read(invitationsNotifierProvider.notifier).accept(i['id'] as String),
                  onReject: () => ref.read(invitationsNotifierProvider.notifier).reject(i['id'] as String),
                )),
          ],
          if (outgoing.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Sent invitations', style: TextStyle(fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
            const SizedBox(height: 8),
            ...outgoing.map((i) => _InvitationTile(
                  title: i['to_email'] as String? ?? '',
                  subtitle: 'Waiting for them to accept',
                  isIncoming: false,
                  onCancel: () => ref.read(invitationsNotifierProvider.notifier).cancelOutgoing(i['id'] as String),
                )),
          ],
          if (connections.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Contacts', style: TextStyle(fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: connections
                  .map((c) => Chip(
                        label: Text(c['display_name'] as String),
                        backgroundColor: BillyTheme.emerald50,
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Groups', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
              TextButton.icon(
                onPressed: () => _createGroupDialog(connections),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
              ),
            ],
          ),
          if (groups.isEmpty)
            Text('No groups yet. Create one to organize shared expenses.', style: TextStyle(fontSize: 13, color: BillyTheme.gray500))
          else
            ...groups.map((g) {
              final members = (g['expense_group_members'] as List?) ?? [];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: BillyTheme.gray100)),
                  title: Text(g['name'] as String? ?? 'Group'),
                  subtitle: Text('${members.length} members · tap for shared expenses'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => GroupExpensesScreen(
                          groupId: g['id'] as String,
                          groupName: g['name'] as String? ?? 'Group',
                          members: List<Map<String, dynamic>>.from(members.map((m) => Map<String, dynamic>.from(m as Map))),
                        ),
                      ),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (connections.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.person_add_alt_outlined),
                          onPressed: () => _pickMembersForGroup(g['id'] as String, connections),
                        ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          if (lbAsync.hasError) ...[
            Material(
              color: BillyTheme.red500.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Could not load transactions. ${lbAsync.error}',
                        style: const TextStyle(fontSize: 13, color: BillyTheme.gray800),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.read(lendBorrowProvider.notifier).refresh(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'To collect',
                  amount: collectTotal,
                  currencyCode: currency,
                  active: _activeTab == 'collect',
                  isCollect: true,
                  onTap: () => setState(() => _activeTab = 'collect'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  label: 'To pay back',
                  amount: payTotal,
                  currencyCode: currency,
                  active: _activeTab == 'pay',
                  isCollect: false,
                  onTap: () => setState(() => _activeTab = 'pay'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by name',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          ...displayed.map((e) => _EntryRow(
                entry: e,
                viewerUid: uid,
                currencyCode: currency,
                onSettle: () => ref.read(lendBorrowProvider.notifier).settle(e['id'] as String),
              )),
          TextButton.icon(
            onPressed: () => _showAddEntrySheet(connections, groups),
            icon: const Icon(Icons.add),
            label: const Text('Add transaction'),
          ),
        ],
      ),
    );
  }
}

class _InvitationTile extends StatelessWidget {
  const _InvitationTile({
    required this.title,
    required this.subtitle,
    required this.isIncoming,
    this.onAccept,
    this.onReject,
    this.onCancel,
  });
  final String title;
  final String subtitle;
  final bool isIncoming;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: isIncoming
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.close, color: BillyTheme.red500), onPressed: onReject),
                  IconButton(icon: const Icon(Icons.check, color: BillyTheme.emerald600), onPressed: onAccept),
                ],
              )
            : TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.currencyCode,
    required this.active,
    required this.isCollect,
    required this.onTap,
  });
  final String label;
  final double amount;
  final String? currencyCode;
  final bool active;
  final bool isCollect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final formatted = AppCurrency.format(amount, currencyCode);
    final activeGradient = isCollect
        ? [BillyTheme.green400, BillyTheme.emerald600]
        : [BillyTheme.red400, const Color(0xFFEF4444)];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: active ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: activeGradient) : null,
          color: active ? null : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: active ? null : Border.all(color: BillyTheme.gray100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: active ? Colors.white.withValues(alpha: 0.85) : BillyTheme.gray500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatted,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : BillyTheme.gray800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.viewerUid,
    required this.currencyCode,
    required this.onSettle,
  });
  final Map<String, dynamic> entry;
  final String? viewerUid;
  final String? currencyCode;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final name = otherPartyDisplayName(entry, viewerUid);
    final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
    final myType = effectiveTypeForViewer(entry, viewerUid);
    final isLent = myType == 'lent';
    final formatted = AppCurrency.format(amount, currencyCode);
    final linked = entry['counterparty_user_id'] != null;
    final roleLine = lendBorrowRoleLine(entry, viewerUid);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: BillyTheme.gray100)),
          leading: CircleAvatar(
            backgroundColor: BillyTheme.emerald50,
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: BillyTheme.emerald600)),
          ),
          title: Text(name),
          subtitle: Text(
            linked ? '$roleLine · Linked' : roleLine,
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatted, style: TextStyle(fontWeight: FontWeight.w700, color: isLent ? BillyTheme.emerald600 : BillyTheme.red500)),
              IconButton(icon: const Icon(Icons.check_circle_outline), onPressed: onSettle),
            ],
          ),
        ),
      ),
    );
  }
}
