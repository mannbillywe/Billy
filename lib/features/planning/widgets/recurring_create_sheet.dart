import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/recurring_provider.dart';

class RecurringCreateSheet extends ConsumerStatefulWidget {
  const RecurringCreateSheet({super.key});

  @override
  ConsumerState<RecurringCreateSheet> createState() => _RecurringCreateSheetState();
}

class _RecurringCreateSheetState extends ConsumerState<RecurringCreateSheet> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  DateTime _anchorDate = DateTime.now();
  String _cadence = 'monthly';
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchorDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _anchorDate = picked);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (title.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill in all fields')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(recurringSeriesProvider.notifier).addSeries(
            title: title,
            amount: amount,
            cadence: _cadence,
            anchorDate: DateFormat('yyyy-MM-dd').format(_anchorDate),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: BillyTheme.red500),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text('New recurring bill', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
            const SizedBox(height: 4),
            const Text('Track a subscription or regular payment', style: TextStyle(fontSize: 13, color: BillyTheme.gray500)),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'Bill name',
                hintText: 'e.g. Netflix, Rent, Insurance',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _cadence,
              decoration: InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              items: const [
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'biweekly', child: Text('Biweekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
                DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
              ],
              onChanged: (v) => setState(() => _cadence = v ?? 'monthly'),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: BillyTheme.gray50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: BillyTheme.gray200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 18, color: BillyTheme.gray400),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('dd MMM yyyy').format(_anchorDate),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray800),
                    ),
                    const Spacer(),
                    const Text('First due date', style: TextStyle(fontSize: 12, color: BillyTheme.gray400)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: BillyTheme.emerald600,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create recurring bill', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
