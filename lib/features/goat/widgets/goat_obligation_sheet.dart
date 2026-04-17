import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_setup_models.dart';
import '../providers/goat_setup_providers.dart';
import 'goat_form_primitives.dart';

/// Bottom-sheet form to create or edit a `goat_obligations` row.
Future<bool?> showGoatObligationSheet(
  BuildContext context, {
  GoatObligation? initial,
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
    builder: (_) =>
        GoatObligationSheet(initial: initial, onSaved: onSaved),
  );
}

class GoatObligationSheet extends ConsumerStatefulWidget {
  final GoatObligation? initial;
  final VoidCallback? onSaved;

  const GoatObligationSheet({super.key, this.initial, this.onSaved});

  @override
  ConsumerState<GoatObligationSheet> createState() =>
      _GoatObligationSheetState();
}

class _GoatObligationSheetState extends ConsumerState<GoatObligationSheet> {
  final _formKey = GlobalKey<FormState>();
  final _lenderCtrl = TextEditingController();
  final _outstandingCtrl = TextEditingController();
  final _monthlyCtrl = TextEditingController();
  final _dueDayCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();

  late GoatObligationType _type;
  late GoatObligationCadence _cadence;
  late GoatObligationStatus _status;

  bool _saving = false;
  bool _deleting = false;
  String? _errorMsg;

  bool get _isEdit => widget.initial?.id != null;

  @override
  void initState() {
    super.initState();
    final o = widget.initial;
    _type = o?.type ?? GoatObligationType.emi;
    _cadence = o?.cadence ?? GoatObligationCadence.monthly;
    _status = o?.status ?? GoatObligationStatus.active;
    _lenderCtrl.text = o?.lenderName ?? '';
    if (o?.currentOutstanding != null) {
      _outstandingCtrl.text = _fmt(o!.currentOutstanding!);
    }
    if (o?.monthlyDue != null) {
      _monthlyCtrl.text = _fmt(o!.monthlyDue!);
    }
    if (o?.dueDay != null) _dueDayCtrl.text = '${o!.dueDay}';
    if (o?.interestRate != null) _rateCtrl.text = _fmt(o!.interestRate!);
  }

  @override
  void dispose() {
    _lenderCtrl.dispose();
    _outstandingCtrl.dispose();
    _monthlyCtrl.dispose();
    _dueDayCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _errorMsg = null;
    });

    final draft = GoatObligation(
      id: widget.initial?.id,
      type: _type,
      lenderName: _lenderCtrl.text.trim().isEmpty ? null : _lenderCtrl.text,
      currentOutstanding: _parseD(_outstandingCtrl.text),
      monthlyDue: _parseD(_monthlyCtrl.text),
      dueDay: _parseInt(_dueDayCtrl.text),
      interestRate: _parseD(_rateCtrl.text),
      cadence: _cadence,
      status: _status,
    );

    try {
      final ctrl = ref.read(goatObligationsControllerProvider.notifier);
      if (_isEdit) {
        await ctrl.save(draft);
      } else {
        await ctrl.create(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Obligation updated' : 'Obligation added'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMsg = 'Couldn\'t save. Try again.';
      });
    }
  }

  Future<void> _confirmDelete() async {
    final id = widget.initial?.id;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove this obligation?'),
        content: const Text(
            'Goat Mode will stop forecasting this payment. You can add it back later.'),
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
      await ref.read(goatObligationsControllerProvider.notifier).delete(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Obligation removed'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _errorMsg = 'Couldn\'t remove this obligation.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GoatSheetScaffold(
      title: _isEdit ? 'Edit obligation' : 'Add an obligation',
      subtitle: _isEdit
          ? 'Update amounts or change cadence.'
          : 'EMIs, rent, insurance — things that must go out every month.',
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
            label: _isEdit ? 'Save changes' : 'Add obligation',
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
                  _deleting ? 'Removing…' : 'Remove obligation',
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
            GoatChipPicker<GoatObligationType>(
              label: 'Type',
              options: GoatObligationType.values,
              selected: _type,
              labelFor: (t) => t.label,
              onChanged: (t) => setState(() => _type = t),
            ),
            const SizedBox(height: 16),
            GoatLabeledField(
              label: 'Who is it with (optional)',
              hint: 'Bank / landlord / provider',
              controller: _lenderCtrl,
              maxLength: 80,
              autofocus: !_isEdit,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GoatLabeledField(
                    label: 'Monthly due',
                    hint: '0',
                    controller: _monthlyCtrl,
                    prefix: '\u20B9 ',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    validator: (v) => goatValidateNonNegativeAmount(v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GoatLabeledField(
                    label: 'Outstanding',
                    hint: '0',
                    controller: _outstandingCtrl,
                    prefix: '\u20B9 ',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    validator: (v) => goatValidateNonNegativeAmount(v),
                    helper: 'Optional',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GoatLabeledField(
                    label: 'Due day (1–31)',
                    hint: 'e.g. 5',
                    controller: _dueDayCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => goatValidateIntRange(
                      v,
                      min: 1,
                      max: 31,
                      required: false,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GoatLabeledField(
                    label: 'Interest rate',
                    hint: '0.0',
                    suffix: '% p.a.',
                    controller: _rateCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    validator: (v) => goatValidateNonNegativeAmount(v, max: 999),
                    helper: 'Optional',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GoatChipPicker<GoatObligationCadence>(
              label: 'How often',
              options: GoatObligationCadence.values,
              selected: _cadence,
              labelFor: (c) => c.label,
              onChanged: (c) => setState(() => _cadence = c),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 16),
              GoatChipPicker<GoatObligationStatus>(
                label: 'Status',
                options: GoatObligationStatus.values,
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

  static double? _parseD(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return double.tryParse(s.trim());
  }

  static int? _parseInt(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return int.tryParse(s.trim());
  }
}
