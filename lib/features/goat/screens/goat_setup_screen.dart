import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_inputs_models.dart';
import '../providers/goat_inputs_providers.dart';
import '../services/goat_inputs_service.dart';

/// Setup surface for GOAT Mode. Users fill in monthly income + planning
/// preferences (one row in goat_user_inputs), then manage goals and
/// obligations. All writes go through RLS; nothing admin here.
class GoatSetupScreen extends ConsumerStatefulWidget {
  const GoatSetupScreen({super.key});

  @override
  ConsumerState<GoatSetupScreen> createState() => _GoatSetupScreenState();
}

class _GoatSetupScreenState extends ConsumerState<GoatSetupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: BillyTheme.scaffoldBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: BillyTheme.gray800),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'GOAT Mode setup',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: BillyTheme.gray800,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: BillyTheme.gray100),
            ),
            child: TabBar(
              controller: _tabs,
              labelColor: Colors.white,
              unselectedLabelColor: BillyTheme.gray600,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF047857), Color(0xFF059669)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorPadding: const EdgeInsets.all(4),
              dividerHeight: 0,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
              tabs: const [
                Tab(text: 'Profile'),
                Tab(text: 'Goals'),
                Tab(text: 'Obligations'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ProfileTab(),
          _GoalsTab(),
          _ObligationsTab(),
        ],
      ),
    );
  }
}

// ─── shared pieces ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.kicker, required this.title, this.subtitle});
  final String kicker;
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: BillyTheme.gray400,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: BillyTheme.gray800,
            letterSpacing: -0.3,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 12.5,
              color: BillyTheme.gray500,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: 14),
      ],
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: child,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.hint});
  final String text;
  final String? hint;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: BillyTheme.gray700,
            letterSpacing: 0.1,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(
            hint!,
            style: const TextStyle(
              fontSize: 11,
              color: BillyTheme.gray500,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

InputDecoration _inputDeco({String? hint, String? prefix, String? suffix}) {
  return InputDecoration(
    hintText: hint,
    prefixText: prefix,
    suffixText: suffix,
    hintStyle: const TextStyle(color: BillyTheme.gray400, fontSize: 14),
    isDense: true,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    filled: true,
    fillColor: BillyTheme.gray50,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: BillyTheme.gray100),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: BillyTheme.gray100),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: BillyTheme.emerald600, width: 1.4),
    ),
  );
}

class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final Map<T, String> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((e) {
        final selected = e.key == value;
        return GestureDetector(
          onTap: () => onChanged(selected ? null : e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? BillyTheme.emerald600 : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? BillyTheme.emerald600
                    : BillyTheme.gray100,
              ),
            ),
            child: Text(
              e.value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : BillyTheme.gray700,
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

// ─── profile tab (goat_user_inputs) ────────────────────────────────────────

class _ProfileTab extends ConsumerStatefulWidget {
  const _ProfileTab();
  @override
  ConsumerState<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<_ProfileTab> {
  final _form = GlobalKey<FormState>();
  final _income = TextEditingController();
  final _salaryDay = TextEditingController();
  final _effMonths = TextEditingController();
  final _liquidity = TextEditingController();
  final _household = TextEditingController();
  final _dependents = TextEditingController();
  final _horizon = TextEditingController();
  String? _payFreq;
  String? _risk;
  String? _tone;
  String _currency = 'INR';
  bool _hydrated = false;
  bool _saving = false;

  @override
  void dispose() {
    _income.dispose();
    _salaryDay.dispose();
    _effMonths.dispose();
    _liquidity.dispose();
    _household.dispose();
    _dependents.dispose();
    _horizon.dispose();
    super.dispose();
  }

  void _hydrate(GoatUserInputs inputs) {
    _income.text = _fmtNum(inputs.monthlyIncome);
    _salaryDay.text = _fmtInt(inputs.salaryDay);
    _effMonths.text = _fmtNum(inputs.emergencyFundTargetMonths);
    _liquidity.text = _fmtNum(inputs.liquidityFloor);
    _household.text = _fmtInt(inputs.householdSize);
    _dependents.text = _fmtInt(inputs.dependents);
    _horizon.text = _fmtInt(inputs.planningHorizonMonths);
    _payFreq = inputs.payFrequency;
    _risk = inputs.riskTolerance;
    _tone = inputs.tonePreference;
    _currency = inputs.incomeCurrency;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final inputs = GoatUserInputs(
      monthlyIncome: double.tryParse(_income.text.trim()),
      incomeCurrency: _currency,
      payFrequency: _payFreq,
      salaryDay: int.tryParse(_salaryDay.text.trim()),
      emergencyFundTargetMonths: double.tryParse(_effMonths.text.trim()),
      liquidityFloor: double.tryParse(_liquidity.text.trim()),
      householdSize: int.tryParse(_household.text.trim()),
      dependents: int.tryParse(_dependents.text.trim()),
      riskTolerance: _risk,
      planningHorizonMonths: int.tryParse(_horizon.text.trim()),
      tonePreference: _tone,
    );
    try {
      await GoatInputsService.upsertUserInputs(inputs);
      ref.invalidate(goatUserInputsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved — the next analysis will use this.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't save: $e"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(goatUserInputsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorState(error: e.toString()),
      data: (inputs) {
        if (!_hydrated) {
          _hydrate(inputs ?? GoatUserInputs.empty);
          _hydrated = true;
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(
                  kicker: 'INCOME',
                  title: 'How you earn',
                  subtitle:
                      'Used for budgeting math, cashflow forecasts, and goal pacing. You can leave any field blank — the backend degrades gracefully.',
                ),
                _FieldCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FieldLabel('Monthly income',
                          hint:
                              'Take-home after taxes, averaged over a typical month.'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          SizedBox(
                            width: 70,
                            child: DropdownButtonFormField<String>(
                              initialValue: _currency,
                              isDense: true,
                              decoration: _inputDeco(),
                              items: const [
                                DropdownMenuItem(
                                    value: 'INR', child: Text('INR')),
                                DropdownMenuItem(
                                    value: 'USD', child: Text('USD')),
                                DropdownMenuItem(
                                    value: 'EUR', child: Text('EUR')),
                                DropdownMenuItem(
                                    value: 'GBP', child: Text('GBP')),
                              ],
                              onChanged: (v) => setState(() {
                                _currency = v ?? 'INR';
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _income,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]')),
                              ],
                              decoration: _inputDeco(hint: 'e.g. 75000'),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                final n = double.tryParse(v.trim());
                                if (n == null || n < 0) {
                                  return 'Must be 0 or more';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Pay frequency'),
                      const SizedBox(height: 8),
                      _ChipRow<String>(
                        options: goatPayFrequencies,
                        value: _payFreq,
                        onChanged: (v) => setState(() => _payFreq = v),
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Salary day',
                          hint:
                              'Day of month when you usually get paid (1–31). Leave blank if it varies.'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _salaryDay,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        decoration: _inputDeco(hint: 'e.g. 1'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = int.tryParse(v.trim());
                          if (n == null || n < 1 || n > 31) {
                            return 'Between 1 and 31';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const _SectionHeader(
                  kicker: 'SAFETY NETS',
                  title: 'Your buffers',
                  subtitle:
                      'Targets the analysis uses for liquidity warnings and risk scoring.',
                ),
                _FieldCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FieldLabel('Emergency fund target',
                          hint:
                              'Months of expenses you want to keep as a safety buffer.'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _effMonths,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: _inputDeco(hint: 'e.g. 6', suffix: 'months'),
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Liquidity floor',
                          hint:
                              'Minimum balance across liquid accounts below which we should warn you.'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _liquidity,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: _inputDeco(hint: 'e.g. 25000'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const _SectionHeader(
                  kicker: 'HOUSEHOLD',
                  title: 'Who you plan for',
                  subtitle:
                      'Helps calibrate per-person metrics and dependent-sensitive advice.',
                ),
                _FieldCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('Household size'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _household,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _inputDeco(hint: 'e.g. 3'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('Dependents'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _dependents,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _inputDeco(hint: 'e.g. 1'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const _SectionHeader(
                  kicker: 'PREFERENCES',
                  title: 'How you want to plan',
                  subtitle: 'Sets the tone and horizon of future analyses.',
                ),
                _FieldCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FieldLabel('Risk tolerance'),
                      const SizedBox(height: 8),
                      _ChipRow<String>(
                        options: goatRiskToleranceLabels,
                        value: _risk,
                        onChanged: (v) => setState(() => _risk = v),
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Coaching tone'),
                      const SizedBox(height: 8),
                      _ChipRow<String>(
                        options: goatToneLabels,
                        value: _tone,
                        onChanged: (v) => setState(() => _tone = v),
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Planning horizon',
                          hint: 'Months ahead to project (1–60).'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _horizon,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        decoration: _inputDeco(hint: 'e.g. 24', suffix: 'months'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = int.tryParse(v.trim());
                          if (n == null || n < 1 || n > 60) {
                            return 'Between 1 and 60';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: BillyTheme.emerald600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save profile'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can update these anytime — changes take effect in the next analysis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: BillyTheme.gray400,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _fmtNum(double? v) =>
    v == null ? '' : (v == v.toInt() ? v.toInt().toString() : v.toString());
String _fmtInt(int? v) => v?.toString() ?? '';

// ─── goals tab ────────────────────────────────────────────────────────────

class _GoalsTab extends ConsumerWidget {
  const _GoalsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(goatGoalsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorState(error: e.toString()),
      data: (goals) {
        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                const _SectionHeader(
                  kicker: 'YOUR GOALS',
                  title: 'What you\'re saving for',
                  subtitle:
                      'Track target amount, deadline, and priority. The analysis will tell you whether you\'re on pace.',
                ),
                if (goals.isEmpty) const _EmptyGoals(),
                for (final g in goals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _GoalCard(goal: g),
                  ),
                const SizedBox(height: 8),
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () => _openEditor(context, ref),
                backgroundColor: BillyTheme.emerald600,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Add goal',
                  style:
                      TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      {GoatGoal? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _GoalEditorSheet(existing: existing),
    );
    if (saved == true) {
      ref.invalidate(goatGoalsProvider);
    }
  }
}

class _EmptyGoals extends StatelessWidget {
  const _EmptyGoals();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [BillyTheme.emerald50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BillyTheme.emerald100),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: BillyTheme.emerald100),
            ),
            child: const Icon(Icons.flag_rounded,
                color: BillyTheme.emerald600, size: 28),
          ),
          const SizedBox(height: 14),
          const Text(
            'Add your first goal',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: BillyTheme.gray800,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Emergency fund, a trip, a big purchase — anything you\'re working towards. The analysis will show pacing, risks, and what\'s on track.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: BillyTheme.gray500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});
  final GoatGoal goal;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          const _GoalsTab()._openEditor(context, ref, existing: goal);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BillyTheme.gray100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: BillyTheme.gray800,
                      ),
                    ),
                  ),
                  _priorityChip(goal.priority),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                goatGoalTypeLabels[goal.goalType] ?? goal.goalType,
                style: const TextStyle(
                    fontSize: 11,
                    color: BillyTheme.gray500,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: goal.progress,
                        minHeight: 7,
                        backgroundColor: BillyTheme.gray100,
                        valueColor: const AlwaysStoppedAnimation(
                            BillyTheme.emerald600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(goal.progress * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: BillyTheme.emerald700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${_money(goal.currentAmount)}  /  ${_money(goal.targetAmount)}${goal.targetDate != null ? '  ·  by ${_fmtDate(goal.targetDate!)}' : ''}',
                style: const TextStyle(
                  fontSize: 11,
                  color: BillyTheme.gray500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priorityChip(int p) {
    final label = switch (p) {
      1 => 'P1 · highest',
      2 => 'P2',
      3 => 'P3',
      4 => 'P4',
      _ => 'P5 · lowest',
    };
    final color = switch (p) {
      1 => const Color(0xFFB91C1C),
      2 => const Color(0xFFB45309),
      3 => BillyTheme.emerald700,
      _ => BillyTheme.gray500,
    };
    final bg = switch (p) {
      1 => const Color(0xFFFEF2F2),
      2 => const Color(0xFFFFFBEB),
      3 => BillyTheme.emerald50,
      _ => BillyTheme.gray50,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }
}

class _GoalEditorSheet extends ConsumerStatefulWidget {
  const _GoalEditorSheet({this.existing});
  final GoatGoal? existing;
  @override
  ConsumerState<_GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends ConsumerState<_GoalEditorSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _target = TextEditingController();
  final _current = TextEditingController();
  String _type = 'savings';
  int _priority = 3;
  DateTime? _targetDate;
  String _status = 'active';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = e.title;
      _target.text = _fmtNum(e.targetAmount);
      _current.text = _fmtNum(e.currentAmount);
      _type = e.goalType;
      _priority = e.priority;
      _targetDate = e.targetDate;
      _status = e.status;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _current.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? now.add(const Duration(days: 180)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final goal = GoatGoal(
        id: widget.existing?.id ?? '',
        goalType: _type,
        title: _title.text.trim(),
        targetAmount: double.tryParse(_target.text.trim()) ?? 0,
        currentAmount: double.tryParse(_current.text.trim()) ?? 0,
        priority: _priority,
        status: _status,
        targetDate: _targetDate,
      );
      await GoatInputsService.saveGoal(goal);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't save goal: $e"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null || id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this goal?'),
        content: const Text('You can\'t undo this.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await GoatInputsService.deleteGoal(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: BillyTheme.gray300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.existing == null ? 'New goal' : 'Edit goal',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: BillyTheme.gray800,
                ),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Goal type'),
              const SizedBox(height: 8),
              _ChipRow<String>(
                options: goatGoalTypeLabels,
                value: _type,
                onChanged: (v) {
                  if (v != null) setState(() => _type = v);
                },
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Title'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _title,
                decoration: _inputDeco(hint: 'e.g. Emergency fund — 6 months'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title required' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('Target amount'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _target,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                          ],
                          decoration: _inputDeco(hint: 'e.g. 450000'),
                          validator: (v) {
                            final n = double.tryParse((v ?? '').trim());
                            if (n == null || n <= 0) {
                              return 'Must be greater than 0';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('Already saved'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _current,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                          ],
                          decoration: _inputDeco(hint: 'e.g. 95000'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Target date (optional)'),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: BillyTheme.gray50,
                    border: Border.all(color: BillyTheme.gray100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_rounded,
                          color: BillyTheme.gray500, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _targetDate == null
                              ? 'Pick a target date'
                              : _fmtDate(_targetDate!),
                          style: TextStyle(
                            fontSize: 14,
                            color: _targetDate == null
                                ? BillyTheme.gray400
                                : BillyTheme.gray800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_targetDate != null)
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              size: 18, color: BillyTheme.gray500),
                          onPressed: () =>
                              setState(() => _targetDate = null),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Priority'),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _priority = i),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _priority == i
                                ? BillyTheme.emerald600
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _priority == i
                                  ? BillyTheme.emerald600
                                  : BillyTheme.gray100,
                            ),
                          ),
                          child: Text(
                            'P$i',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _priority == i
                                  ? Colors.white
                                  : BillyTheme.gray700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Status'),
              const SizedBox(height: 8),
              _ChipRow<String>(
                options: const {
                  'active': 'Active',
                  'paused': 'Paused',
                  'completed': 'Completed',
                  'abandoned': 'Abandoned',
                },
                value: _status,
                onChanged: (v) {
                  if (v != null) setState(() => _status = v);
                },
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  if (widget.existing != null)
                    IconButton(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFFEF2F2),
                        foregroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.all(14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  if (widget.existing != null) const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: BillyTheme.emerald600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                widget.existing == null
                                    ? 'Add goal'
                                    : 'Save changes',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── obligations tab ──────────────────────────────────────────────────────

class _ObligationsTab extends ConsumerWidget {
  const _ObligationsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(goatObligationsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorState(error: e.toString()),
      data: (items) {
        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                const _SectionHeader(
                  kicker: 'FIXED OBLIGATIONS',
                  title: 'Bills that repeat',
                  subtitle:
                      'Rent, EMIs, insurance, loan minimums. The analysis treats these as must-pay items when projecting cashflow and risk.',
                ),
                if (items.isEmpty) const _EmptyObligations(),
                for (final o in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ObligationCard(item: o),
                  ),
                const SizedBox(height: 8),
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () => _openEditor(context, ref),
                backgroundColor: BillyTheme.emerald600,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Add obligation',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, letterSpacing: 0.2),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      {GoatObligation? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ObligationEditorSheet(existing: existing),
    );
    if (saved == true) {
      ref.invalidate(goatObligationsProvider);
    }
  }
}

class _EmptyObligations extends StatelessWidget {
  const _EmptyObligations();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [BillyTheme.emerald50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BillyTheme.emerald100),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: BillyTheme.emerald100),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: BillyTheme.emerald600, size: 28),
          ),
          const SizedBox(height: 14),
          const Text(
            'No obligations yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: BillyTheme.gray800,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add rent, EMIs, insurance premiums, and loan minimums. The analysis uses them for cashflow safety and missed-payment risk.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: BillyTheme.gray500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ObligationCard extends ConsumerWidget {
  const _ObligationCard({required this.item});
  final GoatObligation item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          const _ObligationsTab()._openEditor(context, ref, existing: item);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BillyTheme.gray100),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: BillyTheme.emerald50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _obligationIcon(item.obligationType),
                  color: BillyTheme.emerald700,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.lenderName?.isNotEmpty == true
                          ? item.lenderName!
                          : (goatObligationTypeLabels[item.obligationType] ??
                              item.obligationType),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: BillyTheme.gray800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${goatObligationTypeLabels[item.obligationType] ?? item.obligationType}'
                      ' · ${goatCadenceLabels[item.cadence] ?? item.cadence}'
                      '${item.dueDay != null ? ' · due ${_ordinal(item.dueDay!)}' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: BillyTheme.gray500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.monthlyDue != null ? _money(item.monthlyDue!) : '—',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: BillyTheme.gray800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _obligationIcon(String t) {
  switch (t) {
    case 'rent':
      return Icons.home_rounded;
    case 'emi':
    case 'loan':
    case 'student_loan':
      return Icons.account_balance_rounded;
    case 'credit_card_min':
      return Icons.credit_card_rounded;
    case 'insurance':
      return Icons.health_and_safety_rounded;
    default:
      return Icons.receipt_rounded;
  }
}

class _ObligationEditorSheet extends ConsumerStatefulWidget {
  const _ObligationEditorSheet({this.existing});
  final GoatObligation? existing;
  @override
  ConsumerState<_ObligationEditorSheet> createState() =>
      _ObligationEditorSheetState();
}

class _ObligationEditorSheetState
    extends ConsumerState<_ObligationEditorSheet> {
  final _form = GlobalKey<FormState>();
  final _lender = TextEditingController();
  final _outstanding = TextEditingController();
  final _monthly = TextEditingController();
  final _dueDay = TextEditingController();
  final _rate = TextEditingController();
  String _type = 'rent';
  String _cadence = 'monthly';
  String _status = 'active';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _lender.text = e.lenderName ?? '';
      _outstanding.text = _fmtNum(e.currentOutstanding);
      _monthly.text = _fmtNum(e.monthlyDue);
      _dueDay.text = _fmtInt(e.dueDay);
      _rate.text = _fmtNum(e.interestRate);
      _type = e.obligationType;
      _cadence = e.cadence;
      _status = e.status;
    }
  }

  @override
  void dispose() {
    _lender.dispose();
    _outstanding.dispose();
    _monthly.dispose();
    _dueDay.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final o = GoatObligation(
        id: widget.existing?.id ?? '',
        obligationType: _type,
        cadence: _cadence,
        status: _status,
        lenderName: _lender.text.trim().isEmpty ? null : _lender.text.trim(),
        currentOutstanding: double.tryParse(_outstanding.text.trim()),
        monthlyDue: double.tryParse(_monthly.text.trim()),
        dueDay: int.tryParse(_dueDay.text.trim()),
        interestRate: double.tryParse(_rate.text.trim()),
      );
      await GoatInputsService.saveObligation(o);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null || id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this obligation?'),
        content: const Text('You can\'t undo this.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await GoatInputsService.deleteObligation(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: BillyTheme.gray300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.existing == null ? 'New obligation' : 'Edit obligation',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: BillyTheme.gray800,
                ),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Type'),
              const SizedBox(height: 8),
              _ChipRow<String>(
                options: goatObligationTypeLabels,
                value: _type,
                onChanged: (v) {
                  if (v != null) setState(() => _type = v);
                },
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Payee / lender'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _lender,
                decoration: _inputDeco(hint: 'e.g. SBI Home Loan'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('Monthly due'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _monthly,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                          ],
                          decoration: _inputDeco(hint: 'e.g. 22500'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('Due day'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _dueDay,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: _inputDeco(hint: 'e.g. 10'),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final n = int.tryParse(v.trim());
                            if (n == null || n < 1 || n > 31) {
                              return '1–31';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('Outstanding balance'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _outstanding,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                          ],
                          decoration: _inputDeco(hint: 'optional'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('Interest rate'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _rate,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                          ],
                          decoration: _inputDeco(hint: 'e.g. 8.5', suffix: '%'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Cadence'),
              const SizedBox(height: 8),
              _ChipRow<String>(
                options: goatCadenceLabels,
                value: _cadence,
                onChanged: (v) {
                  if (v != null) setState(() => _cadence = v);
                },
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Status'),
              const SizedBox(height: 8),
              _ChipRow<String>(
                options: const {
                  'active': 'Active',
                  'paid_off': 'Paid off',
                  'defaulted': 'Defaulted',
                  'cancelled': 'Cancelled',
                },
                value: _status,
                onChanged: (v) {
                  if (v != null) setState(() => _status = v);
                },
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  if (widget.existing != null)
                    IconButton(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFFEF2F2),
                        foregroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.all(14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  if (widget.existing != null) const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: BillyTheme.emerald600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                widget.existing == null
                                    ? 'Add obligation'
                                    : 'Save changes',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── shared bits ──────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFEF4444), size: 32),
            const SizedBox(height: 10),
            const Text(
              "Couldn't load",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: BillyTheme.gray800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: BillyTheme.gray500, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

String _money(num v) {
  final n = v.abs();
  String body;
  if (n >= 10000000) {
    body = '${(n / 10000000).toStringAsFixed(2)} Cr';
  } else if (n >= 100000) {
    body = '${(n / 100000).toStringAsFixed(2)} L';
  } else if (n >= 1000) {
    body = n.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  } else {
    body = n.toStringAsFixed(0);
  }
  return '₹$body';
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _ordinal(int day) {
  final s = day.toString();
  if (day % 100 >= 11 && day % 100 <= 13) return '${s}th';
  switch (day % 10) {
    case 1:
      return '${s}st';
    case 2:
      return '${s}nd';
    case 3:
      return '${s}rd';
    default:
      return '${s}th';
  }
}
