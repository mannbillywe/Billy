import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_setup_models.dart';
import '../providers/goat_setup_providers.dart';
import 'goat_form_primitives.dart';

/// Bottom-sheet form to create or edit a `goat_goals` row. Pass [initial]
/// to edit; pass null to create.
Future<bool?> showGoatGoalSheet(
  BuildContext context, {
  GoatGoal? initial,
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
    builder: (_) => GoatGoalSheet(initial: initial, onSaved: onSaved),
  );
}

class GoatGoalSheet extends ConsumerStatefulWidget {
  final GoatGoal? initial;
  final VoidCallback? onSaved;

  const GoatGoalSheet({super.key, this.initial, this.onSaved});

  @override
  ConsumerState<GoatGoalSheet> createState() => _GoatGoalSheetState();
}

class _GoatGoalSheetState extends ConsumerState<GoatGoalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _currentCtrl = TextEditingController();

  late GoatGoalType _type;
  late int _priority;
  late GoatGoalStatus _status;
  DateTime? _targetDate;

  bool _saving = false;
  bool _deleting = false;
  String? _errorMsg;

  bool get _isEdit => widget.initial?.id != null;

  @override
  void initState() {
    super.initState();
    final g = widget.initial;
    _type = g?.type ?? GoatGoalType.savings;
    _priority = g?.priority ?? 3;
    _status = g?.status ?? GoatGoalStatus.active;
    _targetDate = g?.targetDate;
    _titleCtrl.text = g?.title ?? '';
    if (g != null && g.targetAmount > 0) {
      _targetCtrl.text = _fmt(g.targetAmount);
    }
    if (g != null && g.currentAmount > 0) {
      _currentCtrl.text = _fmt(g.currentAmount);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _targetCtrl.dispose();
    _currentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _errorMsg = null;
    });

    final draft = GoatGoal(
      id: widget.initial?.id,
      type: _type,
      title: _titleCtrl.text.trim(),
      targetAmount: double.parse(_targetCtrl.text.trim()),
      currentAmount:
          double.tryParse(_currentCtrl.text.trim()) ?? 0,
      targetDate: _targetDate,
      priority: _priority,
      status: _status,
    );

    try {
      final ctrl = ref.read(goatGoalsControllerProvider.notifier);
      if (_isEdit) {
        await ctrl.save(draft);
      } else {
        await ctrl.create(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Goal updated' : 'Goal added'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMsg = 'Couldn\'t save this goal. Try again.';
      });
    }
  }

  Future<void> _confirmDelete() async {
    final id = widget.initial?.id;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove this goal?'),
        content: Text(
            'We\'ll stop tracking "${widget.initial!.title}" in Goat Mode.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BillyTheme.red500),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _deleting = true);
    try {
      await ref.read(goatGoalsControllerProvider.notifier).delete(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Goal removed'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _errorMsg = 'Couldn\'t remove this goal.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GoatSheetScaffold(
      title: _isEdit ? 'Edit goal' : 'Add a goal',
      subtitle: _isEdit
          ? 'Update details or change priority.'
          : 'Anything from an emergency fund to a trip — Goat Mode will track the pace.',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
            label: _isEdit ? 'Save changes' : 'Add goal',
            saving: _saving,
            onPressed: _save,
            icon: _isEdit ? Icons.check_rounded : Icons.add_rounded,
          ),
          if (_isEdit) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _deleting ? null : _confirmDelete,
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 16, color: BillyTheme.red500),
                label: Text(
                  _deleting ? 'Removing…' : 'Remove goal',
                  style: const TextStyle(
                    color: BillyTheme.red500,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GoatChipPicker<GoatGoalType>(
              label: 'Goal type',
              options: GoatGoalType.values,
              selected: _type,
              labelFor: (g) => g.label,
              onChanged: (g) => setState(() => _type = g),
            ),
            const SizedBox(height: 16),
            GoatLabeledField(
              label: 'What should we call it?',
              hint: 'e.g. Emergency fund',
              controller: _titleCtrl,
              validator: (v) =>
                  goatValidateRequiredText(v, fieldLabel: 'A title'),
              autofocus: !_isEdit,
              maxLength: 60,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GoatLabeledField(
                    label: 'Target amount',
                    hint: '0',
                    controller: _targetCtrl,
                    prefix: '\u20B9 ',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    validator: (v) => goatValidatePositiveAmount(v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GoatLabeledField(
                    label: 'Saved so far',
                    hint: '0',
                    controller: _currentCtrl,
                    prefix: '\u20B9 ',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    validator: (v) => goatValidateNonNegativeAmount(v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GoatDatePickerField(
              label: 'Target date',
              value: _targetDate,
              onChanged: (d) => setState(() => _targetDate = d),
              helper: 'Helps Goat Mode flag pace risk.',
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
            ),
            const SizedBox(height: 16),
            _PrioritySlider(
              value: _priority,
              onChanged: (p) => setState(() => _priority = p),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 16),
              GoatChipPicker<GoatGoalStatus>(
                label: 'Status',
                options: GoatGoalStatus.values,
                selected: _status,
                labelFor: (s) => s.label,
                onChanged: (s) => setState(() => _status = s),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static String _fmt(num v) =>
      v == v.toInt() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class _PrioritySlider extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _PrioritySlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Priority',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: BillyTheme.gray700,
              ),
            ),
            const Spacer(),
            Text(
              _label(value),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: BillyTheme.emerald700,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: BillyTheme.emerald600,
            inactiveTrackColor: BillyTheme.gray200,
            thumbColor: BillyTheme.emerald600,
            overlayColor: BillyTheme.emerald100,
            trackHeight: 4,
          ),
          child: Slider(
            value: value.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Top',
                  style: TextStyle(
                      fontSize: 11,
                      color: BillyTheme.gray500,
                      fontWeight: FontWeight.w600)),
              Text('Later',
                  style: TextStyle(
                      fontSize: 11,
                      color: BillyTheme.gray500,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  static String _label(int v) => switch (v) {
        1 => 'Top priority',
        2 => 'High',
        3 => 'Normal',
        4 => 'Low',
        5 => 'Someday',
        _ => 'Normal',
      };
}
