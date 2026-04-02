import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/documents_provider.dart';
import '../../../services/supabase_service.dart';
import '../../scanner/models/extracted_receipt.dart';
import '../utils/document_json.dart';

const _kCategories = [
  'Food & Beverage',
  'Dining',
  'Groceries',
  'Transportation',
  'Shopping',
  'Utilities',
  'Maintenance',
  'Equipment',
  'Stationery',
  'Other',
];

/// Edit saved document fields and (when linked) sync `invoices` / `invoice_items`.
class DocumentEditScreen extends ConsumerStatefulWidget {
  const DocumentEditScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<DocumentEditScreen> createState() => _DocumentEditScreenState();
}

class _DocumentEditScreenState extends ConsumerState<DocumentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  String? _loadError;

  late TextEditingController _vendorCtrl;
  late TextEditingController _amountCtrl;
  late TextEditingController _invNumCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _cgstCtrl;
  late TextEditingController _sgstCtrl;
  late TextEditingController _igstCtrl;
  late TextEditingController _discountCtrl;
  late TextEditingController _subtotalCtrl;

  DateTime? _date;
  String _type = 'receipt';
  String _category = 'Other';
  List<LineItem> _lines = [];
  Map<String, dynamic>? _extractedBase;
  String? _invoiceId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _vendorCtrl = TextEditingController();
    _amountCtrl = TextEditingController();
    _invNumCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    _cgstCtrl = TextEditingController(text: '0');
    _sgstCtrl = TextEditingController(text: '0');
    _igstCtrl = TextEditingController(text: '0');
    _discountCtrl = TextEditingController(text: '0');
    _subtotalCtrl = TextEditingController(text: '0');
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final doc = await SupabaseService.fetchDocumentById(widget.documentId);
      if (!mounted) return;
      if (doc == null) {
        setState(() {
          _loadError = 'Document not found';
          _loading = false;
        });
        return;
      }
      final ed = asJsonMap(doc['extracted_data']);
      _extractedBase = ed == null ? <String, dynamic>{} : Map<String, dynamic>.from(ed);
      _invoiceId = ed?['invoice_id']?.toString();

      _vendorCtrl.text = doc['vendor_name'] as String? ?? '';
      _amountCtrl.text = ((doc['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
      _type = doc['type'] as String? ?? 'receipt';
      final desc = doc['description'] as String? ?? '';
      final catEd = stringFromEd(ed, 'category');
      if (catEd != null && catEd.isNotEmpty) {
        _category = _kCategories.contains(catEd) ? catEd : 'Other';
      } else if (desc.isNotEmpty) {
        final first = desc.split(',').first.trim();
        _category = _kCategories.contains(first) ? first : 'Other';
      }

      final ds = doc['date'] as String? ?? '';
      _date = DateTime.tryParse(ds) ?? DateTime.now();

      _invNumCtrl.text = stringFromEd(ed, 'invoice_number') ?? '';
      _notesCtrl.text = stringFromEd(ed, 'notes') ?? '';

      _cgstCtrl.text = doubleFromEd(ed, 'cgst').toString();
      _sgstCtrl.text = doubleFromEd(ed, 'sgst').toString();
      _igstCtrl.text = doubleFromEd(ed, 'igst').toString();
      _discountCtrl.text = doubleFromEd(ed, 'discount').toString();
      final st = doubleFromEd(ed, 'subtotal');
      _subtotalCtrl.text = st > 0 ? st.toString() : '';

      final rawItems = ed == null ? null : ed['line_items'] as List<dynamic>?;
      if (rawItems != null && rawItems.isNotEmpty) {
        _lines = rawItems
            .whereType<Map>()
            .map((e) => LineItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _vendorCtrl.dispose();
    _amountCtrl.dispose();
    _invNumCtrl.dispose();
    _notesCtrl.dispose();
    _cgstCtrl.dispose();
    _sgstCtrl.dispose();
    _igstCtrl.dispose();
    _discountCtrl.dispose();
    _subtotalCtrl.dispose();
    super.dispose();
  }

  double _parseD(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_date ?? DateTime.now());
      final amount = _parseD(_amountCtrl.text);
      final cgst = _parseD(_cgstCtrl.text);
      final sgst = _parseD(_sgstCtrl.text);
      final igst = _parseD(_igstCtrl.text);
      final discount = _parseD(_discountCtrl.text);
      final subtotal = _parseD(_subtotalCtrl.text);
      final taxCombined = cgst + sgst + igst > 0 ? cgst + sgst + igst : _parseD(_amountCtrl.text) - subtotal;

      final ed = Map<String, dynamic>.from(_extractedBase ?? {});
      ed['vendor_name'] = _vendorCtrl.text.trim();
      ed['invoice_date'] = dateStr;
      ed['invoice_number'] = _invNumCtrl.text.trim().isEmpty ? null : _invNumCtrl.text.trim();
      ed['notes'] = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
      ed['category'] = _category;
      ed['line_items'] = _lines.map((e) => e.toJson()).toList();
      ed['cgst'] = cgst;
      ed['sgst'] = sgst;
      ed['igst'] = igst;
      ed['discount'] = discount;
      if (subtotal > 0) ed['subtotal'] = subtotal;
      ed['total_amount'] = amount;
      ed['tax_combined'] = taxCombined;

      final invId = _invoiceId;
      if (invId != null && invId.isNotEmpty) {
        final itemRows = <Map<String, dynamic>>[];
        for (final li in _lines) {
          itemRows.add({
            'invoice_id': invId,
            'user_id': uid,
            'assigned_user_id': null,
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
          invoiceId: invId,
          header: {
            'vendor_name': _vendorCtrl.text.trim().isNotEmpty ? _vendorCtrl.text.trim() : 'Invoice',
            'invoice_number': ed['invoice_number'],
            'invoice_date': dateStr,
            'vendor_gstin': ed['vendor_gstin'],
            'subtotal': subtotal > 0 ? subtotal : null,
            'cgst': cgst,
            'sgst': sgst,
            'igst': igst,
            'discount': discount,
            'total_tax': cgst + sgst + igst > 0 ? cgst + sgst + igst : null,
            'total': amount,
            'currency': ed['currency'] ?? 'INR',
            'payment_status': ed['payment_status'],
          },
          itemRows: itemRows,
        );
      }

      final descOut = _category;
      final taxOut = cgst + sgst + igst > 0 ? cgst + sgst + igst : (taxCombined > 0 ? taxCombined : 0.0);
      final cur = ed['currency']?.toString() ?? 'INR';
      await ref.read(documentsProvider.notifier).updateDocument(
            id: widget.documentId,
            vendorName: _vendorCtrl.text.trim(),
            amount: amount,
            taxAmount: taxOut,
            date: dateStr,
            type: _type,
            description: descOut,
            currency: cur,
            extractedData: ed,
          );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addLine() {
    setState(() {
      _lines.add(LineItem(description: '', quantity: 1, total: 0));
    });
  }

  void _removeLine(int i) {
    setState(() {
      if (i >= 0 && i < _lines.length) _lines.removeAt(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit document')),
        body: const Center(child: CircularProgressIndicator(color: BillyTheme.emerald600)),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit document')),
        body: Center(child: Text(_loadError!)),
      );
    }

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('Edit document'),
        backgroundColor: BillyTheme.scaffoldBg,
        foregroundColor: BillyTheme.gray800,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            TextFormField(
              controller: _vendorCtrl,
              decoration: const InputDecoration(labelText: 'Vendor / company'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Total amount'),
              validator: (v) => _parseD(v ?? '') <= 0 ? 'Enter a valid amount' : null,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(_date == null ? '—' : DateFormat.yMMMd().format(_date!)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            const Text('Type', style: TextStyle(fontWeight: FontWeight.w600)),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'receipt', label: Text('Receipt')),
                ButtonSegment(value: 'invoice', label: Text('Invoice')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _kCategories.contains(_category) ? _category : 'Other',
              decoration: const InputDecoration(labelText: 'Category'),
              items: _kCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _category = v ?? 'Other'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invNumCtrl,
              decoration: const InputDecoration(labelText: 'Invoice number (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 20),
            const Text('Tax & subtotal', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _subtotalCtrl, decoration: const InputDecoration(labelText: 'Subtotal'))),
                const SizedBox(width: 8),
                Expanded(child: TextFormField(controller: _discountCtrl, decoration: const InputDecoration(labelText: 'Discount'))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _cgstCtrl, decoration: const InputDecoration(labelText: 'CGST'))),
                const SizedBox(width: 8),
                Expanded(child: TextFormField(controller: _sgstCtrl, decoration: const InputDecoration(labelText: 'SGST'))),
                const SizedBox(width: 8),
                Expanded(child: TextFormField(controller: _igstCtrl, decoration: const InputDecoration(labelText: 'IGST'))),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Line items', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add), label: const Text('Add line')),
              ],
            ),
            if (_lines.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _invoiceId != null ? 'Edit lines from your scan, or add rows.' : 'Optional — add rows to break down this expense.',
                  style: const TextStyle(fontSize: 13, color: BillyTheme.gray500),
                ),
              ),
            ..._lines.asMap().entries.map((e) {
              final i = e.key;
              final li = e.value;
              return _LineEditorCard(
                key: ValueKey('line_${widget.documentId}_$i'),
                index: i,
                item: li,
                onChanged: (next) {
                  setState(() => _lines[i] = next);
                },
                onDelete: () => _removeLine(i),
              );
            }),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: BillyTheme.emerald600,
              ),
              child: _saving
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineEditorCard extends StatefulWidget {
  const _LineEditorCard({
    super.key,
    required this.index,
    required this.item,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final LineItem item;
  final void Function(LineItem) onChanged;
  final VoidCallback onDelete;

  @override
  State<_LineEditorCard> createState() => _LineEditorCardState();
}

class _LineEditorCardState extends State<_LineEditorCard> {
  late TextEditingController _desc;
  late TextEditingController _qty;
  late TextEditingController _amt;

  @override
  void initState() {
    super.initState();
    _desc = TextEditingController(text: widget.item.description);
    _qty = TextEditingController(text: widget.item.quantity.toString());
    _amt = TextEditingController(text: widget.item.total.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _desc.dispose();
    _qty.dispose();
    _amt.dispose();
    super.dispose();
  }

  void _emit() {
    final qty = int.tryParse(_qty.text.trim()) ?? 1;
    final amt = double.tryParse(_amt.text.replaceAll(',', '').trim()) ?? 0;
    widget.onChanged(widget.item.copyWith(
      description: _desc.text,
      quantity: qty < 1 ? 1 : qty,
      total: amt,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Line ${widget.index + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: widget.onDelete),
              ],
            ),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(labelText: 'Description'),
              onChanged: (_) => _emit(),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Qty'),
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _amt,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount'),
                    onChanged: (_) => _emit(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
