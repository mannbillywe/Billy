import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../lend_borrow_perspective.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/lend_borrow_provider.dart';
import '../../documents/screens/document_detail_screen.dart';
import '../../groups/screens/group_expenses_screen.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/social_provider.dart';

class SplitScreen extends ConsumerStatefulWidget {
  const SplitScreen({super.key});

  @override
  ConsumerState<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends ConsumerState<SplitScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _inviteEmailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _inviteEmailCtrl.dispose();
    super.dispose();
  }

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  /// Net balance with a specific friend: positive = they owe you, negative = you owe them
  double _friendBalance(String? friendId, String? uid) {
    if (friendId == null || uid == null) return 0;
    final entries = ref.read(lendBorrowProvider).valueOrNull ?? [];
    double balance = 0;
    for (final e in entries) {
      if ((e['status'] as String?) != 'pending') continue;
      final cpId = e['counterparty_user_id'] as String?;
      final creatorId = e['user_id'] as String?;
      final amount = (e['amount'] as num?)?.toDouble() ?? 0;
      // Only entries between me and this friend
      if (creatorId == uid && cpId == friendId) {
        balance += (e['type'] == 'lent') ? amount : -amount;
      } else if (creatorId == friendId && cpId == uid) {
        balance += (e['type'] == 'lent') ? -amount : amount;
      }
    }
    return balance;
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
    final netBalance = collectTotal - payTotal;

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNetBalanceHero(netBalance, collectTotal, payTotal, currency),
                if (connections.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildRecentFriends(connections, uid, currency),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(
            TabBar(
              controller: _tabCtrl,
              labelColor: BillyTheme.emerald700,
              unselectedLabelColor: BillyTheme.gray400,
              indicatorColor: BillyTheme.emerald600,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: BillyTheme.gray100,
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              tabs: [
                Tab(text: 'IOUs (${pending.length})'),
                Tab(text: 'Groups (${groups.length})'),
                Tab(text: 'Contacts (${connections.length})'),
              ],
            ),
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildIOUTab(pending, uid, currency, connections, groups),
          _buildGroupsTab(groups, connections),
          _buildContactsTab(connections, invitations, uid, currency),
        ],
      ),
    );
  }

  Widget _buildNetBalanceHero(double net, double collect, double pay, String? currency) {
    final isPositive = net >= 0;
    final groupCount = ref.read(expenseGroupsNotifierProvider).valueOrNull?.length ?? 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF047857), Color(0xFF065F46)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isPositive ? 'OWED TO YOU' : 'YOU OWE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppCurrency.format(net.abs(), currency),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          if (groupCount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.trending_up_rounded, size: 16, color: Colors.white.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Text(
                  'Across $groupCount active group${groupCount != 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text('To collect', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.65))),
                      const SizedBox(height: 4),
                      Text(AppCurrency.format(collect, currency), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                    ],
                  ),
                ),
                Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.2)),
                Expanded(
                  child: Column(
                    children: [
                      Text('To pay', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.65))),
                      const SizedBox(height: 4),
                      Text(AppCurrency.format(pay, currency), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFFCA5A5))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentFriends(List<Map<String, dynamic>> connections, String? uid, String? currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Friends',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
            ),
            GestureDetector(
              onTap: () => _tabCtrl.animateTo(2),
              child: const Text(
                'View All',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillyTheme.emerald600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: connections.length.clamp(0, 6) + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (_, i) {
              if (i == connections.length.clamp(0, 6)) {
                return GestureDetector(
                  onTap: () => _tabCtrl.animateTo(2),
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: BillyTheme.gray100,
                          shape: BoxShape.circle,
                          border: Border.all(color: BillyTheme.gray200, width: 2),
                        ),
                        child: const Icon(Icons.add_rounded, size: 24, color: BillyTheme.gray500),
                      ),
                      const SizedBox(height: 6),
                      const Text('Add', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BillyTheme.gray500)),
                    ],
                  ),
                );
              }
              final c = connections[i];
              final name = c['display_name'] as String? ?? 'User';
              return Column(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: BillyTheme.emerald100,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: BillyTheme.emerald700),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 56,
                    child: Text(
                      name.split(' ').first,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BillyTheme.gray700),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── IOU Tab ──────────────────────────────────────────────────────────────

  Widget _buildIOUTab(List<Map<String, dynamic>> pending, String? uid, String? currency,
      List<Map<String, dynamic>> connections, List<Map<String, dynamic>> groups) {
    final collectEntries = pending.where((e) => effectiveTypeForViewer(e, uid) == 'lent').toList();
    final payEntries = pending.where((e) => effectiveTypeForViewer(e, uid) != 'lent').toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      children: [
        if (lbHasError)
          _buildErrorBanner(),
        if (collectEntries.isNotEmpty) ...[
          _SectionLabel(label: 'To collect', count: collectEntries.length),
          const SizedBox(height: 8),
          ...collectEntries.map((e) => _IOUCard(
                entry: e,
                viewerUid: uid,
                currency: currency,
                isCollect: true,
                onSettle: () => _confirmSettle(e, uid, currency),
                onViewDoc: () => _viewDocument(e),
              )),
          const SizedBox(height: 20),
        ],
        if (payEntries.isNotEmpty) ...[
          _SectionLabel(label: 'To pay back', count: payEntries.length),
          const SizedBox(height: 8),
          ...payEntries.map((e) => _IOUCard(
                entry: e,
                viewerUid: uid,
                currency: currency,
                isCollect: false,
                onSettle: () => _confirmSettle(e, uid, currency),
                onViewDoc: () => _viewDocument(e),
              )),
        ],
        if (collectEntries.isEmpty && payEntries.isEmpty)
          _buildEmptyState(
            icon: Icons.handshake_outlined,
            title: 'All settled up',
            subtitle: 'No pending IOUs. Add one to track money between friends.',
          ),
        const SizedBox(height: 16),
        _buildAddButton('Add IOU', Icons.add_rounded, () => _showAddEntrySheet(connections, groups)),
      ],
    );
  }

  bool get lbHasError => ref.watch(lendBorrowProvider).hasError;

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 20, color: BillyTheme.red500),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Could not load data', style: TextStyle(fontSize: 13, color: BillyTheme.gray800)),
          ),
          TextButton(
            onPressed: () => ref.read(lendBorrowProvider.notifier).refresh(),
            style: TextButton.styleFrom(
              foregroundColor: BillyTheme.red500,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSettle(Map<String, dynamic> entry, String? uid, String? currency) async {
    final name = otherPartyDisplayName(entry, uid);
    final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Settle up?'),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 15, color: BillyTheme.gray700),
            children: [
              const TextSpan(text: 'Mark '),
              TextSpan(text: AppCurrency.format(amount, currency), style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' with $name as settled?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: BillyTheme.gray500)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: BillyTheme.emerald600),
            child: const Text('Settle'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(lendBorrowProvider.notifier).settle(entry['id'] as String);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Settled with $name'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: BillyTheme.emerald600,
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

  void _viewDocument(Map<String, dynamic> entry) {
    final docId = entry['document_id']?.toString();
    if (docId != null && docId.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DocumentDetailScreen(documentId: docId)),
      );
    }
  }

  // ─── Groups Tab ───────────────────────────────────────────────────────────

  Widget _buildGroupsTab(List<Map<String, dynamic>> groups, List<Map<String, dynamic>> connections) {
    // Build quick lookup from userId to display name
    final connMap = <String, String>{};
    for (final c in connections) {
      final id = c['other_user_id'] as String?;
      final name = c['display_name'] as String? ?? 'User';
      if (id != null) connMap[id] = name;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      children: [
        if (groups.isEmpty)
          _buildEmptyState(
            icon: Icons.group_outlined,
            title: 'No groups yet',
            subtitle: 'Create a group to split expenses with friends.',
          )
        else
          ...groups.map((g) {
            final members = (g['expense_group_members'] as List?) ?? [];
            final memberNames = members.map((m) {
              final mMap = m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
              final userId = mMap['user_id'] as String?;
              return connMap[userId] ?? 'You';
            }).toList();
            return _GroupCard(
              name: g['name'] as String? ?? 'Group',
              memberCount: members.length,
              memberNames: memberNames,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GroupExpensesScreen(
                      groupId: g['id'] as String,
                      groupName: g['name'] as String? ?? 'Group',
                      members: List<Map<String, dynamic>>.from(
                        members.map((m) => Map<String, dynamic>.from(m as Map)),
                      ),
                    ),
                  ),
                );
              },
              onAddMembers: connections.isNotEmpty
                  ? () => _pickMembersForGroup(g['id'] as String, connections)
                  : null,
            );
          }),
        const SizedBox(height: 16),
        _buildAddButton('New group', Icons.group_add_outlined, () => _createGroupDialog(connections)),
      ],
    );
  }

  // ─── Contacts Tab ─────────────────────────────────────────────────────────

  Widget _buildContactsTab(List<Map<String, dynamic>> connections, List<Map<String, dynamic>> invitations, String? uid, String? currency) {
    final outgoing = invitations.where((i) => i['from_user_id'] == uid && i['status'] == 'pending').toList();
    final incoming = invitations.where((i) => i['from_user_id'] != uid && i['status'] == 'pending').toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      children: [
        // Invite bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BillyTheme.gray100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Invite a friend', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
              const SizedBox(height: 4),
              const Text('They\'ll be able to see linked transactions', style: TextStyle(fontSize: 12, color: BillyTheme.gray500)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inviteEmailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'friend@email.com',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        filled: true,
                        fillColor: BillyTheme.gray50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: BillyTheme.gray200)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: BillyTheme.gray200)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: BillyTheme.emerald600, width: 2)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () async {
                      final em = _inviteEmailCtrl.text.trim();
                      if (em.isEmpty) return;
                      try {
                        await ref.read(invitationsNotifierProvider.notifier).inviteEmail(em);
                        _inviteEmailCtrl.clear();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Invitation sent'),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: BillyTheme.emerald600,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Invite'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BillyTheme.emerald600,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (incoming.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel(label: 'Pending for you', count: incoming.length),
          const SizedBox(height: 8),
          ...incoming.map((i) => _InvitationCard(
                email: i['to_email'] as String? ?? '',
                isIncoming: true,
                onAccept: () => ref.read(invitationsNotifierProvider.notifier).accept(i['id'] as String),
                onReject: () => ref.read(invitationsNotifierProvider.notifier).reject(i['id'] as String),
              )),
        ],
        if (outgoing.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel(label: 'Sent invitations', count: outgoing.length),
          const SizedBox(height: 8),
          ...outgoing.map((i) => _InvitationCard(
                email: i['to_email'] as String? ?? '',
                isIncoming: false,
                onCancel: () => ref.read(invitationsNotifierProvider.notifier).cancelOutgoing(i['id'] as String),
              )),
        ],
        if (connections.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel(label: 'Your contacts', count: connections.length),
          const SizedBox(height: 8),
          ...connections.map((c) {
            final otherId = c['other_user_id'] as String?;
            final name = c['display_name'] as String;
            final balance = _friendBalance(otherId, uid);
            return _ContactCard(name: name, balance: balance, currency: currency);
          }),
        ],
        if (connections.isEmpty && incoming.isEmpty && outgoing.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: _buildEmptyState(
              icon: Icons.person_add_outlined,
              title: 'No contacts yet',
              subtitle: 'Invite friends by email to start splitting expenses.',
            ),
          ),
      ],
    );
  }

  // ─── Shared helpers ───────────────────────────────────────────────────────

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: BillyTheme.gray100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 32, color: BillyTheme.gray400),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: BillyTheme.gray600)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: BillyTheme.gray400), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildAddButton(String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BillyTheme.emerald600, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: BillyTheme.emerald600),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.emerald600)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Sheets & dialogs ─────────────────────────────────────────────────────

  Future<void> _showAddEntrySheet(List<Map<String, dynamic>> connections, List<Map<String, dynamic>> groups) async {
    final totalAmountCtrl = TextEditingController();
    String type = 'lent';
    String? groupId;
    final profile = ref.read(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;
    final symbol = AppCurrency.formatter(currency).currencySymbol;

    // Multiple people support: list of (name, linkedUserId, customAmount)
    var people = <_PersonEntry>[_PersonEntry()];

    // Splitting mode: equal or custom
    String splitMode = 'equal';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final totalRaw = totalAmountCtrl.text.trim().replaceAll(',', '.');
          final totalAmount = double.tryParse(totalRaw) ?? 0;
          final perPerson = people.isNotEmpty && totalAmount > 0 ? totalAmount / people.length : 0.0;

          return Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 20),
                  const Text('New IOU', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
                  const SizedBox(height: 4),
                  Text(
                    people.length > 1 ? 'Split between ${people.length} people' : 'Track money between you and a friend',
                    style: const TextStyle(fontSize: 13, color: BillyTheme.gray500),
                  ),
                  const SizedBox(height: 20),
                  // Type toggle
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: BillyTheme.gray100, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        _sheetToggle('I lent', type == 'lent', BillyTheme.emerald600, () => setSheet(() => type = 'lent')),
                        const SizedBox(width: 4),
                        _sheetToggle('I borrowed', type == 'borrowed', BillyTheme.red500, () => setSheet(() => type = 'borrowed')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Total amount
                  TextField(
                    controller: totalAmountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                    onChanged: (_) => setSheet(() {}),
                    decoration: InputDecoration(
                      labelText: 'Total amount',
                      prefixText: '$symbol ',
                      prefixStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                  if (groups.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: groupId,
                      decoration: InputDecoration(
                        labelText: 'Group (optional)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('No group')),
                        ...groups.map((g) => DropdownMenuItem<String?>(
                              value: g['id'] as String,
                              child: Text(g['name'] as String? ?? 'Group'),
                            )),
                      ],
                      onChanged: (v) => setSheet(() => groupId = v),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Split mode toggle (only show when >1 person)
                  if (people.length > 1) ...[
                    Row(
                      children: [
                        const Text('Split:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillyTheme.gray700)),
                        const SizedBox(width: 8),
                        _miniPill('Equal', splitMode == 'equal', () => setSheet(() => splitMode = 'equal')),
                        const SizedBox(width: 6),
                        _miniPill('Custom', splitMode == 'custom', () => setSheet(() => splitMode = 'custom')),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  // People list
                  ...List.generate(people.length, (i) {
                    final p = people[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: BillyTheme.gray50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: BillyTheme.gray200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: connections.isNotEmpty
                                    ? DropdownButtonFormField<String?>(
                                        value: p.linkedUserId,
                                        decoration: InputDecoration(
                                          labelText: 'Person ${i + 1}',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          isDense: true,
                                        ),
                                        items: [
                                          const DropdownMenuItem<String?>(value: null, child: Text('Type name below')),
                                          ...connections.map((c) => DropdownMenuItem<String?>(
                                                value: c['other_user_id'] as String,
                                                child: Text(c['display_name'] as String),
                                              )),
                                        ],
                                        onChanged: (v) => setSheet(() {
                                          p.linkedUserId = v;
                                          if (v != null) {
                                            for (final c in connections) {
                                              if (c['other_user_id'] == v) {
                                                p.nameCtrl.text = c['display_name'] as String? ?? '';
                                                break;
                                              }
                                            }
                                          }
                                        }),
                                      )
                                    : TextField(
                                        controller: p.nameCtrl,
                                        decoration: InputDecoration(
                                          labelText: 'Person ${i + 1} name',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          isDense: true,
                                        ),
                                      ),
                              ),
                              if (people.length > 1) ...[
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 20, color: BillyTheme.red500),
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  padding: EdgeInsets.zero,
                                  onPressed: () => setSheet(() {
                                    people[i].dispose();
                                    people.removeAt(i);
                                  }),
                                ),
                              ],
                            ],
                          ),
                          if (connections.isNotEmpty && p.linkedUserId == null) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: p.nameCtrl,
                              decoration: InputDecoration(
                                labelText: 'Custom name',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                isDense: true,
                              ),
                            ),
                          ],
                          if (splitMode == 'custom') ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: p.amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Custom amount',
                                prefixText: '$symbol ',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                isDense: true,
                              ),
                            ),
                          ] else if (people.length > 1 && totalAmount > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${AppCurrency.format(perPerson, currency)} each',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BillyTheme.emerald600),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  // Add person button
                  TextButton.icon(
                    onPressed: () => setSheet(() => people.add(_PersonEntry())),
                    icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                    label: const Text('Add another person'),
                    style: TextButton.styleFrom(foregroundColor: BillyTheme.emerald600),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      if (totalAmount <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
                        return;
                      }
                      for (final p in people) {
                        if (p.nameCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Enter a name for every person')));
                          return;
                        }
                      }
                      Navigator.pop(ctx);
                      try {
                        for (var i = 0; i < people.length; i++) {
                          final p = people[i];
                          double amt;
                          if (splitMode == 'custom') {
                            amt = double.tryParse(p.amountCtrl.text.trim().replaceAll(',', '.')) ?? 0;
                            if (amt <= 0) amt = perPerson;
                          } else {
                            // Equal split — last person gets the remainder to avoid rounding issues
                            if (i == people.length - 1) {
                              final priorSum = perPerson * (people.length - 1);
                              amt = totalAmount - ((priorSum * 100).round() / 100);
                            } else {
                              amt = (perPerson * 100).round() / 100;
                            }
                          }
                          await ref.read(lendBorrowProvider.notifier).addEntry(
                                counterpartyName: p.nameCtrl.text.trim(),
                                amount: amt,
                                type: type,
                                counterpartyUserId: p.linkedUserId,
                                groupId: groupId,
                              );
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(people.length > 1 ? '${people.length} IOUs saved' : 'IOU saved'),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: BillyTheme.emerald600,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not save: $e'), backgroundColor: BillyTheme.red500, behavior: SnackBarBehavior.floating),
                          );
                        }
                      } finally {
                        for (final p in people) { p.dispose(); }
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: type == 'lent' ? BillyTheme.emerald600 : BillyTheme.red500,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      people.length > 1
                          ? '${type == 'lent' ? 'Record lending' : 'Record borrowing'} (${people.length} people)'
                          : type == 'lent' ? 'Record lending' : 'Record borrowing',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _miniPill(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? BillyTheme.emerald600 : BillyTheme.gray100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : BillyTheme.gray500)),
      ),
    );
  }

  Widget _sheetToggle(String label, bool active, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)] : null,
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: active ? color : BillyTheme.gray400)),
        ),
      ),
    );
  }

  Future<void> _createGroupDialog(List<Map<String, dynamic>> connections) async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New group'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. Roommates, Trip to Goa',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: BillyTheme.gray500))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: BillyTheme.emerald600),
            child: const Text('Create'),
          ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                  activeColor: BillyTheme.emerald600,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            FilledButton(
              onPressed: () async {
                for (final id in chosen) {
                  await ref.read(expenseGroupsNotifierProvider.notifier).addMember(groupId: groupId, memberUserId: id);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(backgroundColor: BillyTheme.emerald600),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Extracted widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this._tabBar);
  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: BillyTheme.scaffoldBg, child: _tabBar);
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) => false;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray700)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: BillyTheme.gray200, borderRadius: BorderRadius.circular(10)),
          child: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillyTheme.gray600)),
        ),
      ],
    );
  }
}

class _IOUCard extends StatelessWidget {
  const _IOUCard({
    required this.entry,
    required this.viewerUid,
    required this.currency,
    required this.isCollect,
    required this.onSettle,
    required this.onViewDoc,
  });
  final Map<String, dynamic> entry;
  final String? viewerUid;
  final String? currency;
  final bool isCollect;
  final VoidCallback onSettle;
  final VoidCallback onViewDoc;

  @override
  Widget build(BuildContext context) {
    final name = otherPartyDisplayName(entry, viewerUid);
    final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
    final formatted = AppCurrency.format(amount, currency);
    final linked = entry['counterparty_user_id'] != null;
    final hasDoc = entry['document_id'] != null && entry['document_id'].toString().isNotEmpty;
    final creatorId = entry['user_id']?.toString();
    final isCreator = viewerUid != null && creatorId == viewerUid;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isCollect ? BillyTheme.emerald50 : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isCollect ? BillyTheme.emerald600 : BillyTheme.red500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (linked) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: BillyTheme.emerald50, borderRadius: BorderRadius.circular(6)),
                            child: const Text('Linked', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: BillyTheme.emerald600)),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          isCollect ? 'owes you' : 'you owe',
                          style: const TextStyle(fontSize: 12, color: BillyTheme.gray500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Amount + actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatted,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isCollect ? BillyTheme.emerald600 : BillyTheme.red500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasDoc && isCreator)
                        _miniAction(Icons.receipt_long_outlined, BillyTheme.gray500, onViewDoc),
                      _miniAction(Icons.check_circle_rounded, BillyTheme.emerald600, onSettle),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniAction(IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.name, required this.memberCount, required this.onTap, this.onAddMembers, this.memberNames = const []});
  final String name;
  final int memberCount;
  final VoidCallback onTap;
  final VoidCallback? onAddMembers;
  final List<String> memberNames;

  static const _groupIcons = <String, IconData>{
    'apartment': Icons.home_rounded,
    'living': Icons.home_rounded,
    'house': Icons.home_rounded,
    'rent': Icons.home_rounded,
    'roommate': Icons.home_rounded,
    'trip': Icons.flight_rounded,
    'travel': Icons.flight_rounded,
    'vacation': Icons.flight_rounded,
    'food': Icons.restaurant_rounded,
    'dinner': Icons.restaurant_rounded,
    'lunch': Icons.restaurant_rounded,
    'office': Icons.business_rounded,
    'work': Icons.business_rounded,
  };

  IconData _icon() {
    final lower = name.toLowerCase();
    for (final entry in _groupIcons.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return Icons.group_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final membersText = memberNames.isNotEmpty
        ? memberNames.take(3).join(', ') + (memberNames.length > 3 ? ' +${memberNames.length - 3} more' : '')
        : '$memberCount ${memberCount == 1 ? 'member' : 'members'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: BillyTheme.emerald50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Icon(_icon(), size: 24, color: BillyTheme.emerald600),
                  ),
                  const Spacer(),
                  if (onAddMembers != null)
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_outlined, size: 20, color: BillyTheme.gray400),
                      onPressed: onAddMembers,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
              const SizedBox(height: 4),
              Text(
                membersText,
                style: const TextStyle(fontSize: 13, color: BillyTheme.gray500),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: BillyTheme.gray50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$memberCount ${memberCount == 1 ? 'member' : 'members'}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BillyTheme.gray600),
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded, color: BillyTheme.gray300, size: 22),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({required this.email, required this.isIncoming, this.onAccept, this.onReject, this.onCancel});
  final String email;
  final bool isIncoming;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isIncoming ? const Color(0xFFFEF3C7) : BillyTheme.gray100,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              isIncoming ? Icons.mail_outlined : Icons.schedule,
              size: 18,
              color: isIncoming ? const Color(0xFFD97706) : BillyTheme.gray500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
                Text(
                  isIncoming ? 'Wants to connect' : 'Waiting for reply',
                  style: const TextStyle(fontSize: 11, color: BillyTheme.gray500),
                ),
              ],
            ),
          ),
          if (isIncoming) ...[
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              color: BillyTheme.red500,
              onPressed: onReject,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.check_rounded, size: 20),
              color: BillyTheme.emerald600,
              onPressed: onAccept,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
          ] else
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(foregroundColor: BillyTheme.gray500, padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: const Text('Cancel', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _PersonEntry {
  final nameCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  String? linkedUserId;

  void dispose() {
    nameCtrl.dispose();
    amountCtrl.dispose();
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.name, this.balance = 0, this.currency});
  final String name;
  final double balance;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final hasBalance = balance.abs() > 0.01;
    final owesYou = balance > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: BillyTheme.emerald50,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(fontWeight: FontWeight.w700, color: BillyTheme.emerald600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
                if (hasBalance)
                  Text(
                    owesYou ? 'owes you' : 'you owe',
                    style: TextStyle(fontSize: 11, color: owesYou ? BillyTheme.emerald600 : BillyTheme.red500),
                  )
                else
                  const Text('Settled up', style: TextStyle(fontSize: 11, color: BillyTheme.gray400)),
              ],
            ),
          ),
          if (hasBalance)
            Text(
              AppCurrency.format(balance.abs(), currency),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: owesYou ? BillyTheme.emerald600 : BillyTheme.red500,
              ),
            ),
        ],
      ),
    );
  }
}
