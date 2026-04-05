import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/group_expenses_provider.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/lend_borrow_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/social_provider.dart';
import '../../../services/supabase_service.dart';
import '../../documents/models/document_category_source.dart';
import '../../groups/screens/group_expenses_screen.dart';
import '../models/extracted_receipt.dart';

/// Review/edit extraction, select line items, optionally split to a group or record lend/borrow.
class ScanReviewPanel extends ConsumerStatefulWidget {
  const ScanReviewPanel({
    super.key,
    required this.initialReceipt,
    this.invoiceId,
    required this.onDiscard,
    required this.onDone,
  });

  final ExtractedReceipt initialReceipt;
  /// When set, header + line items are written back to `invoices` / `invoice_items`.
  final String? invoiceId;
  final VoidCallback onDiscard;
  /// After successful save (e.g. pop route + snackbar handled by parent).
  final VoidCallback onDone;

  @override
  ConsumerState<ScanReviewPanel> createState() => _ScanReviewPanelState();
}

class _ScanReviewPanelState extends ConsumerState<ScanReviewPanel> {
  late final TextEditingController _vendorCtrl;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _invCtrl;
  late final TextEditingController _catCtrl;
  late final TextEditingController _notesCtrl;
  late final List<bool> _lineOn;
  late final List<String?> _lineAssignee;
  String? _singleAssignee;
  bool _useGroup = false;
  String? _groupId;
  bool _useLend = false;
  String _lendType = 'lent';
  final _counterpartyCtrl = TextEditingController();
  String? _linkedUserId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.initialReceipt;
    _vendorCtrl = TextEditingController(text: r.vendorName);
    _dateCtrl = TextEditingController(text: r.date);
    _invCtrl = TextEditingController(text: r.invoiceNumber ?? '');
    _catCtrl = TextEditingController(text: r.category ?? '');
    _notesCtrl = TextEditingController(text: r.notes ?? '');
    _lineOn = List.generate(r.lineItems.length, (_) => true);
    _lineAssignee = List.generate(r.lineItems.length, (_) => null);
  }

  @override
  void dispose() {
    _vendorCtrl.dispose();
    _dateCtrl.dispose();
    _invCtrl.dispose();
    _catCtrl.dispose();
    _notesCtrl.dispose();
    _counterpartyCtrl.dispose();
    super.dispose();
  }

  ExtractedReceipt _buildReceipt() {
    final r = widget.initialReceipt;
    return r.copyWith(
      vendorName: _vendorCtrl.text.trim(),
      date: _dateCtrl.text.trim().isNotEmpty ? _dateCtrl.text.trim() : r.date,
      invoiceNumber: _invCtrl.text.trim().isEmpty ? null : _invCtrl.text.trim(),
      category: _catCtrl.text.trim().isEmpty ? null : _catCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
  }

  double _allocationTotal(ExtractedReceipt r) {
    if (r.lineItems.isEmpty) return r.total;
    var s = 0.0;
    for (var i = 0; i < r.lineItems.length; i++) {
      if (i < _lineOn.length && _lineOn[i]) s += r.lineItems[i].total;
    }
    return s;
  }

  Map<String, dynamic> _extractedPayload(ExtractedReceipt draft, double alloc) {
    return draft.toJson()
      ..['line_selection'] = [
        for (var i = 0; i < draft.lineItems.length; i++)
          {
            'index': i,
            'included': i < _lineOn.length ? _lineOn[i] : false,
            'assigned_user_id': i < _lineAssignee.length ? _lineAssignee[i] : null,
          }
      ]
      ..['allocation_total'] = alloc
      ..['invoice_id'] = widget.invoiceId
      ..['intent_group_expense'] = _useGroup && _groupId != null
      ..['group_id'] = _groupId
      ..['intent_lend_borrow'] = _useLend
      ..['lend_type'] = _useLend ? _lendType : null
      ..['lend_counterparty'] = _useLend ? _counterpartyCtrl.text.trim() : null;
  }

  List<Map<String, dynamic>> _membersForGroup(String? gid, List<Map<String, dynamic>> groups) {
    if (gid == null) return [];
    Map<String, dynamic>? g;
    for (final x in groups) {
      if (x['id'] == gid) {
        g = x;
        break;
      }
    }
    if (g == null) return [];
    final raw = g['expense_group_members'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Line selection total, or invoice header total / subtotal when lines are off or empty.
  double _effectiveAllocation(ExtractedReceipt draft) {
    var a = _allocationTotal(draft);
    if (a <= 0 && draft.total > 0) return draft.total;
    if (a <= 0 && draft.subtotal > 0) return draft.subtotal;
    return a;
  }

  Future<void> _save() async {
    if (_saving) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final draft = _buildReceipt();
    final alloc = _effectiveAllocation(draft);
    if (alloc <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one line item with an amount, or fix totals.')),
      );
      return;
    }

    if (_useGroup) {
      if (_groupId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a group')));
        return;
      }
      final groups = ref.read(expenseGroupsNotifierProvider).valueOrNull ?? [];
      final members = _membersForGroup(_groupId, groups);
      if (members.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group has no members')));
        return;
      }
      if (draft.lineItems.isEmpty) {
        if (_singleAssignee == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assign to a member')));
          return;
        }
      } else {
        for (var i = 0; i < draft.lineItems.length; i++) {
          if (!_lineOn[i]) continue;
          if ((_lineAssignee[i] ?? '').isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Assign member for line: ${draft.lineItems[i].description}')),
            );
            return;
          }
        }
      }
    }

    if (_useLend) {
      final name = _counterpartyCtrl.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter counterparty name')));
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final taxStored = draft.cgst + draft.sgst + draft.igst > 0 ? draft.cgst + draft.sgst + draft.igst : draft.tax;
      final descParts = <String>{};
      if (draft.category != null) descParts.add(draft.category!);
      for (var i = 0; i < draft.lineItems.length; i++) {
        if (_lineOn[i] && draft.lineItems[i].category != null) descParts.add(draft.lineItems[i].category!);
      }

      final categoryId =
          descParts.isNotEmpty ? await SupabaseService.resolveCategoryIdByName(descParts.first) : null;

      final extractedPayload = _extractedPayload(draft, alloc);

      if (widget.invoiceId != null) {
        final iid = widget.invoiceId!;
        final itemRows = <Map<String, dynamic>>[];
        for (var i = 0; i < draft.lineItems.length; i++) {
          if (i >= _lineOn.length || !_lineOn[i]) continue;
          final li = draft.lineItems[i];
          itemRows.add({
            'invoice_id': iid,
            'user_id': uid,
            'assigned_user_id': _useGroup ? _lineAssignee[i] : null,
            'description': li.description,
            'quantity': li.quantity,
            'unit_price': li.unitPrice,
            'amount': li.total,
            'tax_percent': li.taxPercent,
            'tax_amount': li.taxAmount,
            'item_code': li.hsnCode,
            'category': li.category,
          });
        }
        await SupabaseService.syncInvoiceAfterReview(
          invoiceId: iid,
          header: {
            'vendor_name': draft.vendorName.isNotEmpty ? draft.vendorName : 'Invoice',
            'invoice_number': draft.invoiceNumber,
            'invoice_date': draft.date.isNotEmpty ? draft.date : DateTime.now().toIso8601String().split('T').first,
            'vendor_gstin': draft.vendorGstin,
            'subtotal': draft.subtotal,
            'cgst': draft.cgst,
            'sgst': draft.sgst,
            'igst': draft.igst,
            'discount': draft.discount,
            'total_tax': draft.tax,
            'total': draft.total,
            'currency': draft.currency,
            'payment_status': draft.paymentStatus,
          },
          itemRows: itemRows,
        );
      }

      final docAmount = draft.total > 0 ? draft.total : alloc;
      final docDate = draft.date.isNotEmpty ? draft.date : DateTime.now().toIso8601String().substring(0, 10);

      final savedDocId = await ref.read(documentsProvider.notifier).addDocument(
            vendorName: draft.vendorName.isNotEmpty ? draft.vendorName : 'Invoice',
            amount: docAmount,
            taxAmount: taxStored,
            date: docDate,
            type: (draft.invoiceNumber != null && draft.invoiceNumber!.isNotEmpty) ? 'invoice' : 'receipt',
            description: descParts.isEmpty ? null : descParts.join(', '),
            paymentMethod: draft.paymentMethod,
            currency: draft.currency,
            extractedData: extractedPayload,
            categoryId: categoryId,
            categorySource: DocumentCategorySource.ai,
          );

      if (_useGroup && _groupId != null) {
        final agg = <String, double>{};
        if (draft.lineItems.isEmpty) {
          final a = _singleAssignee;
          if (a != null) agg[a] = alloc;
        } else {
          for (var i = 0; i < draft.lineItems.length; i++) {
            if (!_lineOn[i]) continue;
            final assignee = _lineAssignee[i];
            if (assignee == null) continue;
            agg[assignee] = (agg[assignee] ?? 0) + draft.lineItems[i].total;
          }
        }
        final shares = _sharesFromAgg(agg, alloc);
        if (shares.isEmpty) throw StateError('No shares computed');
        await SupabaseService.createGroupExpense(
          groupId: _groupId!,
          title: draft.vendorName.isNotEmpty ? draft.vendorName : 'Invoice split',
          amount: alloc,
          paidByUserId: uid,
          expenseDate: DateTime.tryParse(draft.date) ?? DateTime.now(),
          shares: shares,
        );
        ref.invalidate(groupExpensesProvider(_groupId!));
        ref.invalidate(expenseGroupsNotifierProvider);
      }

      if (_useLend) {
        await ref.read(lendBorrowProvider.notifier).addEntry(
              counterpartyName: _counterpartyCtrl.text.trim(),
              amount: alloc,
              type: _lendType,
              notes: draft.notes,
              counterpartyUserId: _linkedUserId,
              groupId: _groupId,
              documentId: savedDocId,
            );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Saved', style: TextStyle(fontWeight: FontWeight.w700)),
            backgroundColor: BillyTheme.emerald600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
      widget.onDone();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: BillyTheme.red500),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Saves a `documents` row with `status: draft` only — no invoice sync, group expense, or lend/borrow.
  Future<void> _saveAsDraft() async {
    if (_saving) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final draft = _buildReceipt();
    final alloc = _effectiveAllocation(draft);
    final amount = alloc > 0 ? alloc : draft.total;

    setState(() => _saving = true);
    try {
      final taxStored = draft.cgst + draft.sgst + draft.igst > 0 ? draft.cgst + draft.sgst + draft.igst : draft.tax;
      final descParts = <String>{};
      if (draft.category != null) descParts.add(draft.category!);
      for (var i = 0; i < draft.lineItems.length; i++) {
        if (i < _lineOn.length && _lineOn[i] && draft.lineItems[i].category != null) {
          descParts.add(draft.lineItems[i].category!);
        }
      }

      final categoryId =
          descParts.isNotEmpty ? await SupabaseService.resolveCategoryIdByName(descParts.first) : null;

      final extractedPayload = _extractedPayload(draft, alloc)..['scan_draft'] = true;
      final docDate = draft.date.isNotEmpty ? draft.date : DateTime.now().toIso8601String().substring(0, 10);

      await ref.read(documentsProvider.notifier).addDocument(
            vendorName: draft.vendorName.isNotEmpty ? draft.vendorName : 'Draft',
            amount: amount >= 0 ? amount : 0,
            taxAmount: taxStored,
            date: docDate,
            type: (draft.invoiceNumber != null && draft.invoiceNumber!.isNotEmpty) ? 'invoice' : 'receipt',
            description: descParts.isEmpty ? null : descParts.join(', '),
            paymentMethod: draft.paymentMethod,
            currency: draft.currency,
            extractedData: extractedPayload,
            categoryId: categoryId,
            categorySource: DocumentCategorySource.ai,
            status: 'draft',
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Saved as draft', style: TextStyle(fontWeight: FontWeight.w700)),
            backgroundColor: BillyTheme.emerald600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
      widget.onDone();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Draft save failed: $e'), backgroundColor: BillyTheme.red500),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Map<String, dynamic>> _sharesFromAgg(Map<String, double> agg, double targetTotal) {
    double round2(double x) => (x * 100).round() / 100;
    final entries = agg.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) return [];
    var allocated = 0.0;
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < entries.length; i++) {
      final uid = entries[i].key;
      if (i == entries.length - 1) {
        out.add({'user_id': uid, 'share_amount': round2(targetTotal - allocated)});
      } else {
        final v = round2(entries[i].value);
        out.add({'user_id': uid, 'share_amount': v});
        allocated += v;
      }
    }
    return out;
  }

  void _defaultAssignees(List<Map<String, dynamic>> members) {
    final first = members.isNotEmpty ? members.first['user_id'] as String? : null;
    setState(() {
      _singleAssignee = first;
      for (var i = 0; i < _lineAssignee.length; i++) {
        _lineAssignee[i] = first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = _buildReceipt();
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;
    final groupsAsync = ref.watch(expenseGroupsNotifierProvider);
    final groups = groupsAsync.valueOrNull ?? [];
    final connAsync = ref.watch(connectionsNotifierProvider);
    final connections = connAsync.valueOrNull ?? [];
    final members = _membersForGroup(_groupId, groups);
    final alloc = _allocationTotal(draft);
    String memberLabel(Map<String, dynamic> m) {
      final p = m['member_profile'] as Map<String, dynamic>?;
      final n = p?['display_name'] as String?;
      return (n != null && n.isNotEmpty) ? n : 'Member';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Review invoice',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: BillyTheme.zinc950),
        ),
        const SizedBox(height: 8),
        Text('One extraction per photo — edit fields, choose lines, then save.', style: TextStyle(color: BillyTheme.zinc400)),
        const SizedBox(height: 20),
        TextField(
          controller: _vendorCtrl,
          decoration: const InputDecoration(labelText: 'Vendor', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _dateCtrl,
          decoration: const InputDecoration(labelText: 'Bill date (YYYY-MM-DD)', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _invCtrl,
          decoration: const InputDecoration(labelText: 'Invoice number', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _catCtrl,
          decoration: const InputDecoration(labelText: 'Category (invoice)', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        Text('Taxes', style: TextStyle(fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
        const SizedBox(height: 6),
        Text(
          'CGST ${AppCurrency.format(draft.cgst, currency)} · SGST ${AppCurrency.format(draft.sgst, currency)} · IGST ${AppCurrency.format(draft.igst, currency)}'
          '${draft.discount > 0 ? ' · Discount ${AppCurrency.format(draft.discount, currency)}' : ''}',
          style: TextStyle(fontSize: 13, color: BillyTheme.gray600),
        ),
        const SizedBox(height: 8),
        Text('Total ${AppCurrency.format(draft.total, currency)} · Selected for split ${AppCurrency.format(alloc, currency)}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        if (draft.lineItems.isNotEmpty) ...[
          Text('Line items', style: TextStyle(fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
          const SizedBox(height: 8),
          ...List.generate(draft.lineItems.length, (i) {
            final it = draft.lineItems[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: CheckboxListTile(
                value: _lineOn[i],
                onChanged: (v) => setState(() => _lineOn[i] = v ?? false),
                title: Text(it.description, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${AppCurrency.format(it.total, currency)}${it.category != null ? ' · ${it.category}' : ''}'),
                    if (_useGroup && _groupId != null && members.isNotEmpty && _lineOn[i])
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: DropdownButtonFormField<String>(
                          value: _lineAssignee[i] != null && members.any((m) => m['user_id'] == _lineAssignee[i])
                              ? _lineAssignee[i]
                              : members.first['user_id'] as String?,
                          decoration: const InputDecoration(labelText: 'Assign to', isDense: true, border: OutlineInputBorder()),
                          items: [
                            for (final m in members)
                              DropdownMenuItem(
                                value: m['user_id'] as String,
                                child: Text(memberLabel(m)),
                              ),
                          ],
                          onChanged: (v) => setState(() => _lineAssignee[i] = v),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ] else
          Text('No line items — full total will be used for optional split/lend.', style: TextStyle(color: BillyTheme.gray500)),
        if (draft.lineItems.isEmpty && _useGroup && _groupId != null && members.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _singleAssignee ?? members.first['user_id'] as String?,
            decoration: const InputDecoration(labelText: 'Assign full amount to', border: OutlineInputBorder()),
            items: [
              for (final m in members)
                DropdownMenuItem(value: m['user_id'] as String, child: Text(memberLabel(m))),
            ],
            onChanged: (v) => setState(() => _singleAssignee = v),
          ),
        ],
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text('Create group expense from selection'),
          subtitle: const Text('Uses selected lines; shares match assignees'),
          value: _useGroup,
          onChanged: groups.isEmpty
              ? null
              : (v) {
                  setState(() {
                    _useGroup = v;
                    if (v && _groupId == null && groups.isNotEmpty) {
                      _groupId = groups.first['id'] as String;
                      _defaultAssignees(_membersForGroup(_groupId, groups));
                    }
                  });
                },
        ),
        if (_useGroup) ...[
          DropdownButtonFormField<String>(
            value: _groupId != null && groups.any((g) => g['id'] == _groupId) ? _groupId : (groups.isNotEmpty ? groups.first['id'] as String? : null),
            decoration: const InputDecoration(labelText: 'Group', border: OutlineInputBorder()),
            items: [
              for (final g in groups)
                DropdownMenuItem(value: g['id'] as String, child: Text(g['name'] as String? ?? 'Group')),
            ],
            onChanged: (gid) {
              setState(() => _groupId = gid);
              if (gid != null) _defaultAssignees(_membersForGroup(gid, groups));
            },
          ),
          TextButton.icon(
            onPressed: _groupId == null
                ? null
                : () {
                    Map<String, dynamic>? g;
                    for (final x in groups) {
                      if (x['id'] == _groupId) {
                        g = x;
                        break;
                      }
                    }
                    if (g == null) return;
                    final gm = Map<String, dynamic>.from(g);
                    final mem = (gm['expense_group_members'] as List?) ?? [];
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => GroupExpensesScreen(
                          groupId: gm['id'] as String,
                          groupName: gm['name'] as String? ?? 'Group',
                          members: List<Map<String, dynamic>>.from(mem.map((m) => Map<String, dynamic>.from(m as Map))),
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open group'),
          ),
        ],
        SwitchListTile(
          title: const Text('Record lend / borrow'),
          subtitle: Text('Amount = selected lines (${AppCurrency.format(alloc, currency)})'),
          value: _useLend,
          onChanged: (v) => setState(() => _useLend = v),
        ),
        if (_useLend) ...[
          if (connections.isNotEmpty && _linkedUserId == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Link a contact so the other person sees this under the right tab (I lent / I borrowed).',
                style: TextStyle(fontSize: 12, color: BillyTheme.gray500),
              ),
            )
          else if (connections.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Add a friend under People & groups to link them here; otherwise only you will see this entry.',
                style: TextStyle(fontSize: 12, color: BillyTheme.gray500),
              ),
            ),
          Row(
            children: ['lent', 'borrowed'].map((t) {
              final on = _lendType == t;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: t == 'lent' ? 6 : 0, left: t == 'borrowed' ? 6 : 0),
                  child: ChoiceChip(
                    label: Text(t == 'lent' ? 'I lent' : 'I borrowed'),
                    selected: on,
                    onSelected: (_) => setState(() => _lendType = t),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _counterpartyCtrl,
            decoration: const InputDecoration(labelText: 'Counterparty name', border: OutlineInputBorder()),
          ),
          if (connections.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              value: _linkedUserId,
              decoration: const InputDecoration(labelText: 'Link contact (optional)', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('None')),
                for (final c in connections)
                  DropdownMenuItem(value: c['other_user_id'] as String, child: Text(c['display_name'] as String)),
              ],
              onChanged: (v) => setState(() => _linkedUserId = v),
            ),
          ],
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _saving ? null : _saveAsDraft,
            child: const Text('Save as draft'),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: _saving ? null : widget.onDiscard, child: const Text('Start over')),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: BillyTheme.emerald600, padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _saving ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
