import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/budgets_provider.dart';

class BudgetCreateSheet extends ConsumerStatefulWidget {
  const BudgetCreateSheet({super.key});

  @override
  ConsumerState<BudgetCreateSheet> createState() => _BudgetCreateSheetState();
}

class _BudgetCreateSheetState extends ConsumerState<BudgetCreateSheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _period = 'monthly';
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (name.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a name and valid amount')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(budgetsProvider.notifier).addBudget(
            name: name,
            amount: amount,
            period: _period,
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
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New budget', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Budget name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount limit', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _period,
            decoration: const InputDecoration(labelText: 'Period', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
            ],
            onChanged: (v) => setState(() => _period = v ?? 'monthly'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: BillyTheme.emerald600,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create budget'),
          ),
        ],
      ),
    );
  }
}
