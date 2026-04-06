import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/goat_theme.dart';
import '../../../providers/goat_cash_providers.dart';
import '../../../providers/goat_goals_providers.dart';
import 'goals_repository.dart';

/// Optional defaults when opening the create sheet (e.g. from a suggestion).
class CreateGoalPrefill {
  const CreateGoalPrefill({
    this.title,
    this.targetAmountText,
    this.goalType,
    this.targetDate,
    this.forecastReserve,
  });

  final String? title;
  final String? targetAmountText;
  final String? goalType;
  final DateTime? targetDate;
  final String? forecastReserve;
}

Future<void> showCreateGoalSheet(
  BuildContext context,
  WidgetRef ref, {
  CreateGoalPrefill? prefill,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GoatTokens.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => _CreateGoalForm(
      prefill: prefill,
      onDone: () {
        ref.invalidate(goatGoalsProvider);
        ref.invalidate(goatGoalsSummaryProvider);
        ref.invalidate(goatGoalsForecastInputProvider);
        ref.invalidate(goatForecastProvider);
        ref.invalidate(goatGoalRecommendationsProvider);
      },
    ),
  );
}

class _CreateGoalForm extends StatefulWidget {
  const _CreateGoalForm({this.prefill, required this.onDone});
  final CreateGoalPrefill? prefill;
  final VoidCallback onDone;

  @override
  State<_CreateGoalForm> createState() => _CreateGoalFormState();
}

class _CreateGoalFormState extends State<_CreateGoalForm> {
  late final TextEditingController _title;
  late final TextEditingController _target;
  late final TextEditingController _initial;
  DateTime? _targetDate;
  late String _type;
  late String _reserve;
  bool _saving = false;

  static const _types = [
    ('emergency_fund', 'Emergency fund'),
    ('sinking_fund', 'Sinking fund'),
    ('purchase', 'Purchase'),
    ('travel', 'Travel'),
    ('bill_buffer', 'Bill / rent buffer'),
    ('debt_paydown', 'Debt paydown'),
    ('custom', 'Custom'),
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    _title = TextEditingController(text: p?.title ?? '');
    _target = TextEditingController(text: p?.targetAmountText ?? '');
    _initial = TextEditingController(text: '0');
    _targetDate = p?.targetDate;
    _type = p?.goalType ?? 'sinking_fund';
    _reserve = p?.forecastReserve ?? 'soft';
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _initial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 16 + pad),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _type == 'emergency_fund' ? 'Emergency fund' : 'New goal',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: GoatTokens.textPrimary),
            ),
            if (_type == 'emergency_fund')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '3–6 months of essential expenses is a common milestone. You set the target; progress is always deterministic.',
                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.35),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _target,
              decoration: const InputDecoration(labelText: 'Target amount', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _initial,
              decoration: const InputDecoration(labelText: 'Starting balance', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Goal type', border: OutlineInputBorder()),
              items: _types
                  .map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? 'sinking_fund'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _reserve,
              decoration: const InputDecoration(
                labelText: 'Forecast reserve',
                border: OutlineInputBorder(),
                helperText: 'Hard: reduces safe-to-spend by monthly need. Soft: shown in Goals only.',
              ),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('None')),
                DropdownMenuItem(value: 'soft', child: Text('Soft (informational)')),
                DropdownMenuItem(value: 'hard', child: Text('Hard (reduce safe-to-spend)')),
              ],
              onChanged: (v) => setState(() => _reserve = v ?? 'soft'),
            ),
            ListTile(
              title: const Text('Target date (optional)'),
              subtitle: Text(
                _targetDate == null
                    ? 'No date — pace uses contributions only'
                    : '${_targetDate!.year}-${_targetDate!.month.toString().padLeft(2, '0')}-${_targetDate!.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _targetDate ?? DateTime.now().add(const Duration(days: 180)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 15)),
                );
                if (d != null) setState(() => _targetDate = d);
              },
            ),
            if (_targetDate != null)
              TextButton(
                onPressed: () => setState(() => _targetDate = null),
                child: const Text('Clear target date'),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      final tgt = double.tryParse(_target.text.replaceAll(',', '')) ?? 0;
                      if (_title.text.trim().isEmpty || tgt <= 0) return;
                      final ini = double.tryParse(_initial.text.replaceAll(',', '')) ?? 0;
                      setState(() => _saving = true);
                      try {
                        await GoalsRepository.createGoal(
                          title: _title.text.trim(),
                          goalType: _type,
                          targetAmount: tgt,
                          currentAmount: ini,
                          targetDate: _targetDate,
                          forecastReserve: _reserve,
                        );
                        widget.onDone();
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: const Text('Create goal'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAddContributionSheet(
  BuildContext context,
  WidgetRef ref,
  String goalId,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GoatTokens.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => _AddContributionForm(
      goalId: goalId,
      onDone: () {
        ref.invalidate(goatGoalDetailProvider(goalId));
        ref.invalidate(goatGoalsProvider);
        ref.invalidate(goatGoalsSummaryProvider);
        ref.invalidate(goatGoalsForecastInputProvider);
        ref.invalidate(goatForecastProvider);
      },
    ),
  );
}

class _AddContributionForm extends StatefulWidget {
  const _AddContributionForm({required this.goalId, required this.onDone});
  final String goalId;
  final VoidCallback onDone;

  @override
  State<_AddContributionForm> createState() => _AddContributionFormState();
}

class _AddContributionFormState extends State<_AddContributionForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 16 + pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Add contribution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder()),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [500, 1000, 2000, 5000].map((v) {
              return ActionChip(
                label: Text('+$v'),
                onPressed: () => _amount.text = v.toString(),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    final a = double.tryParse(_amount.text.replaceAll(',', '')) ?? 0;
                    if (a <= 0) return;
                    setState(() => _saving = true);
                    try {
                      await GoalsRepository.addContribution(
                        goalId: widget.goalId,
                        amount: a,
                        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                      );
                      widget.onDone();
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
