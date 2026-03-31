import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/documents_provider.dart';

class AddExpenseSheet extends ConsumerStatefulWidget {
  const AddExpenseSheet({super.key});

  @override
  ConsumerState<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<AddExpenseSheet> {
  final _vendorCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  String _type = 'receipt';
  String _category = 'Other';
  bool _saving = false;

  static const _categories = [
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

  @override
  void dispose() {
    _vendorCtrl.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final vendor = _vendorCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (vendor.isEmpty || amount == null || amount <= 0) return;

    setState(() => _saving = true);
    try {
      await ref.read(documentsProvider.notifier).addDocument(
        vendorName: vendor,
        amount: amount,
        taxAmount: 0,
        date: DateFormat('yyyy-MM-dd').format(_date),
        type: _type,
        description: _category,
        paymentMethod: null,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: BillyTheme.red500),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Add Invoice', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
            const SizedBox(height: 4),
            const Text('Enter details manually', style: TextStyle(fontSize: 14, color: BillyTheme.gray500)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: BillyTheme.gray100, borderRadius: BorderRadius.circular(999)),
              child: Row(
                children: ['receipt', 'invoice'].map((t) {
                  final isActive = _type == t;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _type = t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          t[0].toUpperCase() + t.substring(1),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isActive ? BillyTheme.gray800 : BillyTheme.gray400,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            _buildField(_vendorCtrl, 'Vendor / Company name'),
            const SizedBox(height: 12),
            _buildField(_amountCtrl, 'Amount (\$)', keyboard: TextInputType.number),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: BillyTheme.gray50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BillyTheme.gray200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _category,
                  isExpanded: true,
                  items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _category = v ?? 'Other'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray800),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: BillyTheme.gray50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: BillyTheme.gray200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 18, color: BillyTheme.gray400),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('dd MMM yyyy').format(_date),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray800),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildField(_descCtrl, 'Notes (optional)'),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _saving ? null : _save,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _saving ? BillyTheme.gray300 : BillyTheme.emerald600,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _saving
                      ? null
                      : [BoxShadow(color: BillyTheme.emerald600.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                alignment: Alignment.center,
                child: _saving
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                    : const Text('Save Invoice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, {TextInputType? keyboard}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: label,
        filled: true,
        fillColor: BillyTheme.gray50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: BillyTheme.gray200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: BillyTheme.gray200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: BillyTheme.emerald600, width: 2)),
      ),
    );
  }
}
