import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_setup_models.dart';
import '../providers/goat_setup_providers.dart';
import 'goat_form_primitives.dart';

/// Bottom-sheet form for `goat_user_inputs` (one row per user, upsert).
///
/// UX: contextual, not an onboarding wall. We split the form into three
/// compact sections ("Income", "Safety net", "Preferences"). Every field is
/// optional — saving just some of them is a valid state.
///
/// Use [showGoatUserInputsSheet] to open — it wires up initial values from
/// the Riverpod cache and triggers a post-save hook on success.
Future<bool?> showGoatUserInputsSheet(
  BuildContext context, {
  String? focusedKey,
  VoidCallback? onSaved,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => GoatUserInputsSheet(
      focusedKey: focusedKey,
      onSaved: onSaved,
    ),
  );
}

class GoatUserInputsSheet extends ConsumerStatefulWidget {
  /// Optional "highlight this field" hint when the sheet is opened from a
  /// specific missing-input prompt — we auto-scroll to it and pre-focus the
  /// relevant input. Null means "general setup".
  final String? focusedKey;
  final VoidCallback? onSaved;

  const GoatUserInputsSheet({super.key, this.focusedKey, this.onSaved});

  @override
  ConsumerState<GoatUserInputsSheet> createState() =>
      _GoatUserInputsSheetState();
}

class _GoatUserInputsSheetState extends ConsumerState<GoatUserInputsSheet> {
  final _formKey = GlobalKey<FormState>();

  final _incomeCtrl = TextEditingController();
  final _salaryDayCtrl = TextEditingController();
  final _emergencyMonthsCtrl = TextEditingController();
  final _liquidityCtrl = TextEditingController();
  final _householdCtrl = TextEditingController();
  final _dependentsCtrl = TextEditingController();
  final _horizonCtrl = TextEditingController();

  GoatPayFrequency? _pay;
  GoatRiskTolerance? _risk;
  GoatTonePreference? _tone;

  bool _saving = false;
  String? _errorMsg;
  bool _hydrated = false;

  @override
  void dispose() {
    _incomeCtrl.dispose();
    _salaryDayCtrl.dispose();
    _emergencyMonthsCtrl.dispose();
    _liquidityCtrl.dispose();
    _householdCtrl.dispose();
    _dependentsCtrl.dispose();
    _horizonCtrl.dispose();
    super.dispose();
  }

  void _hydrate(GoatUserInputs v) {
    if (_hydrated) return;
    _hydrated = true;
    if (v.monthlyIncome != null) _incomeCtrl.text = _fmtAmount(v.monthlyIncome!);
    if (v.salaryDay != null) _salaryDayCtrl.text = '${v.salaryDay}';
    if (v.emergencyFundTargetMonths != null) {
      _emergencyMonthsCtrl.text = _fmtAmount(v.emergencyFundTargetMonths!);
    }
    if (v.liquidityFloor != null) {
      _liquidityCtrl.text = _fmtAmount(v.liquidityFloor!);
    }
    if (v.householdSize != null) _householdCtrl.text = '${v.householdSize}';
    if (v.dependents != null) _dependentsCtrl.text = '${v.dependents}';
    if (v.planningHorizonMonths != null) {
      _horizonCtrl.text = '${v.planningHorizonMonths}';
    }
    _pay = v.payFrequency;
    _risk = v.riskTolerance;
    _tone = v.tonePreference;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _errorMsg = null;
    });

    final draft = GoatUserInputs(
      monthlyIncome: _parseAmount(_incomeCtrl.text),
      payFrequency: _pay,
      salaryDay: _parseInt(_salaryDayCtrl.text),
      emergencyFundTargetMonths: _parseAmount(_emergencyMonthsCtrl.text),
      liquidityFloor: _parseAmount(_liquidityCtrl.text),
      householdSize: _parseInt(_householdCtrl.text),
      dependents: _parseInt(_dependentsCtrl.text),
      riskTolerance: _risk,
      planningHorizonMonths: _parseInt(_horizonCtrl.text),
      tonePreference: _tone,
    );

    try {
      await ref.read(goatUserInputsControllerProvider.notifier).save(draft);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Setup saved'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMsg = 'Couldn\'t save. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(goatUserInputsControllerProvider);
    async.whenData(_hydrate);
    // Even if async is in loading we still render the form with empties.

    return GoatSheetScaffold(
      title: 'Improve this analysis',
      subtitle:
          'A few optional details make Goat Mode sharper. Nothing is required.',
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_errorMsg != null) ...[
            Text(
              _errorMsg!,
              style: const TextStyle(
                fontSize: 12.5,
                color: BillyTheme.red500,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
          ],
          GoatPrimaryButton(
            label: 'Save setup',
            saving: _saving,
            onPressed: _save,
            icon: Icons.check_rounded,
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GoatFormSectionHeader('Income'),
            GoatLabeledField(
              label: 'Monthly income (take-home)',
              hint: '0',
              controller: _incomeCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_amountFormatter()],
              prefix: '\u20B9 ',
              helper: 'Helps size your emergency fund and detect drift.',
              validator: (v) => goatValidateNonNegativeAmount(v),
              autofocus: widget.focusedKey == 'monthly_income',
            ),
            const SizedBox(height: 14),
            GoatChipPicker<GoatPayFrequency>(
              label: 'Pay frequency',
              options: GoatPayFrequency.values,
              selected: _pay,
              labelFor: (p) => p.label,
              onChanged: (p) => setState(() => _pay = p),
            ),
            const SizedBox(height: 14),
            GoatLabeledField(
              label: 'Typical salary day (1–31)',
              hint: 'e.g. 28',
              controller: _salaryDayCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) =>
                  goatValidateIntRange(v, min: 1, max: 31, required: false),
              helper: 'Used to forecast when cash lands.',
            ),
            const SizedBox(height: 22),
            const GoatFormSectionHeader('Safety net'),
            GoatLabeledField(
              label: 'Emergency fund target',
              hint: '3',
              controller: _emergencyMonthsCtrl,
              suffix: 'months',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_amountFormatter()],
              validator: (v) =>
                  goatValidateNonNegativeAmount(v, max: 120),
              helper: 'How many months of spend you want to keep on hand.',
              autofocus: widget.focusedKey == 'emergency_fund_target_months',
            ),
            const SizedBox(height: 14),
            GoatLabeledField(
              label: 'Minimum balance you want to hold',
              hint: '0',
              controller: _liquidityCtrl,
              prefix: '\u20B9 ',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_amountFormatter()],
              validator: (v) => goatValidateNonNegativeAmount(v),
              helper: 'We warn you before cashflow dips under this.',
              autofocus: widget.focusedKey == 'liquidity_floor',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GoatLabeledField(
                    label: 'Household size',
                    hint: '1',
                    controller: _householdCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    validator: (v) => goatValidateIntRange(
                      v,
                      min: 0,
                      max: 30,
                      required: false,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GoatLabeledField(
                    label: 'Dependents',
                    hint: '0',
                    controller: _dependentsCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    validator: (v) => goatValidateIntRange(
                      v,
                      min: 0,
                      max: 30,
                      required: false,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const GoatFormSectionHeader('Preferences'),
            GoatChipPicker<GoatRiskTolerance>(
              label: 'Risk tolerance',
              options: GoatRiskTolerance.values,
              selected: _risk,
              labelFor: (r) => r.label,
              onChanged: (r) => setState(() => _risk = r),
            ),
            if (_risk != null) ...[
              const SizedBox(height: 4),
              Text(
                _risk!.hint,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: BillyTheme.gray500,
                ),
              ),
            ],
            const SizedBox(height: 14),
            GoatLabeledField(
              label: 'Planning horizon (months)',
              hint: '12',
              controller: _horizonCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) =>
                  goatValidateIntRange(v, min: 1, max: 60, required: false),
              helper: 'Between 1 and 60.',
            ),
            const SizedBox(height: 14),
            GoatChipPicker<GoatTonePreference>(
              label: 'Tone you prefer',
              options: GoatTonePreference.values,
              selected: _tone,
              labelFor: (t) => t.label,
              onChanged: (t) => setState(() => _tone = t),
            ),
            if (_tone != null) ...[
              const SizedBox(height: 4),
              Text(
                _tone!.hint,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: BillyTheme.gray500,
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// parsing / formatting helpers — liberal input, strict payload
// ──────────────────────────────────────────────────────────────────────────

String _fmtAmount(num v) {
  if (v == v.toInt()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

double? _parseAmount(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final cleaned = s.trim().replaceAll(',', '');
  return double.tryParse(cleaned);
}

int? _parseInt(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  return int.tryParse(s.trim());
}

TextInputFormatter _amountFormatter() {
  return FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));
}
