import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/budgets_provider.dart';
import '../../../services/supabase_service.dart';

class BudgetCreateSheet extends ConsumerStatefulWidget {
  const BudgetCreateSheet({super.key});

  @override
  ConsumerState<BudgetCreateSheet> createState() => _BudgetCreateSheetState();
}

class _BudgetCreateSheetState extends ConsumerState<BudgetCreateSheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _period = 'monthly';
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  bool _saving = false;
  List<Map<String, dynamic>> _categories = [];
  bool _loadingCats = true;

  static const _defaultCategories = [
    'Food & Beverage',
    'Dining',
    'Groceries',
    'Transportation',
    'Shopping',
    'Utilities',
    'Maintenance',
    'Equipment',
    'Stationery',
    'Entertainment',
    'Healthcare',
    'Education',
    'Housing',
    'Subscriptions',
    'Borrow',
    'Lend',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await SupabaseService.fetchCategories();
      if (mounted) {
        setState(() {
          _categories = cats;
          _loadingCats = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCats = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (_selectedCategoryName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a category for this budget')),
      );
      return;
    }
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount greater than zero')),
      );
      return;
    }

    final budgetName = name.isNotEmpty ? name : _selectedCategoryName!;
    setState(() => _saving = true);
    try {
      String? catId = _selectedCategoryId;
      catId ??= await SupabaseService.resolveCategoryIdByName(_selectedCategoryName!);

      await ref.read(budgetsProvider.notifier).addBudget(
            name: budgetName,
            amount: amount,
            period: _period,
            categoryId: catId,
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
    final combinedCats = <String, String?>{};
    for (final c in _categories) {
      combinedCats[c['name'] as String] = c['id'] as String?;
    }
    for (final name in _defaultCategories) {
      combinedCats.putIfAbsent(name, () => null);
    }
    final sortedNames = combinedCats.keys.toList()..sort();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
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
            const Text('New Budget', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
            const SizedBox(height: 4),
            const Text('Set a spending limit for a category', style: TextStyle(fontSize: 13, color: BillyTheme.gray500)),
            const SizedBox(height: 20),

            // Category picker
            const Text('CATEGORY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: BillyTheme.gray400)),
            const SizedBox(height: 8),
            _loadingCats
                ? Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BillyTheme.gray50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: BillyTheme.gray200),
                    ),
                    child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: BillyTheme.emerald600)),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: BillyTheme.gray50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _selectedCategoryName == null ? BillyTheme.gray200 : BillyTheme.emerald600),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedCategoryName,
                        hint: const Text('Select a category', style: TextStyle(fontSize: 14, color: BillyTheme.gray400)),
                        isExpanded: true,
                        items: sortedNames.map((name) {
                          return DropdownMenuItem(value: name, child: Text(name));
                        }).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _selectedCategoryName = v;
                            _selectedCategoryId = combinedCats[v];
                            if (_nameCtrl.text.trim().isEmpty) {
                              _nameCtrl.text = v;
                            }
                          });
                        },
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray800),
                      ),
                    ),
                  ),

            const SizedBox(height: 16),

            // Budget name
            const Text('BUDGET NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: BillyTheme.gray400)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. Monthly Groceries',
                filled: true,
                fillColor: BillyTheme.gray50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: BillyTheme.gray200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: BillyTheme.gray200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: BillyTheme.emerald600, width: 2)),
              ),
            ),

            const SizedBox(height: 16),

            // Amount limit
            const Text('AMOUNT LIMIT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: BillyTheme.gray400)),
            const SizedBox(height: 8),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '10000',
                filled: true,
                fillColor: BillyTheme.gray50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: BillyTheme.gray200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: BillyTheme.gray200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: BillyTheme.emerald600, width: 2)),
              ),
            ),

            const SizedBox(height: 16),

            // Period
            const Text('PERIOD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: BillyTheme.gray400)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: BillyTheme.gray50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BillyTheme.gray200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _period,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                  ],
                  onChanged: (v) => setState(() => _period = v ?? 'monthly'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray800),
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
                  : const Text('Create Budget', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
