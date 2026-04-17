import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/billy_theme.dart';

/// Small, repo-consistent form primitives used by every Goat Mode setup
/// sheet. These intentionally stay humble: Billy doesn't have a shared
/// currency field or validator library, so we build the simplest possible
/// wrappers that match existing form styling (plan_screen / document_edit).
///
/// Motion is deliberately subtle — no bounce, no flourish. Form inputs
/// should feel predictable.

class GoatSheetScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;

  const GoatSheetScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: BillyTheme.gray200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: BillyTheme.gray800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: BillyTheme.gray500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: child,
              ),
            ),
            if (footer != null)
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: BillyTheme.gray100),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: footer,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A calm labeled text field with a single-line helper caption.
/// Uses `TextFormField` so it plays nicely inside a [Form].
class GoatLabeledField extends StatelessWidget {
  final String label;
  final String? hint;
  final String? helper;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final List<TextInputFormatter>? inputFormatters;
  final String? prefix;
  final String? suffix;
  final int? maxLength;
  final bool autofocus;

  const GoatLabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.keyboardType,
    this.validator,
    this.inputFormatters,
    this.prefix,
    this.suffix,
    this.maxLength,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: label),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          inputFormatters: inputFormatters,
          autofocus: autofocus,
          maxLength: maxLength,
          style: const TextStyle(
            fontSize: 14.5,
            color: BillyTheme.gray800,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            hintStyle: const TextStyle(
              fontSize: 14,
              color: BillyTheme.gray400,
              fontWeight: FontWeight.w500,
            ),
            prefixText: prefix,
            suffixText: suffix,
            prefixStyle: const TextStyle(
              fontSize: 14,
              color: BillyTheme.gray500,
              fontWeight: FontWeight.w700,
            ),
            suffixStyle: const TextStyle(
              fontSize: 13,
              color: BillyTheme.gray500,
              fontWeight: FontWeight.w600,
            ),
            filled: true,
            fillColor: BillyTheme.gray50,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: BillyTheme.gray100),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: BillyTheme.gray100),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: BillyTheme.emerald500),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: BillyTheme.red400),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: BillyTheme.red500),
            ),
            errorStyle: const TextStyle(
              fontSize: 11.5,
              color: BillyTheme.red500,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper!,
            style: const TextStyle(
              fontSize: 11.5,
              color: BillyTheme.gray500,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

/// A one-of-N picker using pill-shaped chips. Used for pay_frequency,
/// risk_tolerance, tone_preference, goal_type, obligation_type, cadence,
/// and status. Keeps the form short and tappable.
class GoatChipPicker<T> extends StatelessWidget {
  final String label;
  final List<T> options;
  final T? selected;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;
  final bool wrap;

  const GoatChipPicker({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
    this.wrap = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final opt in options) _chip(opt),
          ],
        ),
      ],
    );
  }

  Widget _chip(T opt) {
    final isSel = opt == selected;
    return InkWell(
      onTap: () => onChanged(opt),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSel ? BillyTheme.emerald600 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSel ? BillyTheme.emerald600 : BillyTheme.gray200,
          ),
        ),
        child: Text(
          labelFor(opt),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSel ? Colors.white : BillyTheme.gray700,
          ),
        ),
      ),
    );
  }
}

/// A tappable row that opens a date picker.
class GoatDatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? helper;

  const GoatDatePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: label),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now.add(const Duration(days: 30)),
              firstDate: firstDate ?? DateTime(now.year - 1),
              lastDate: lastDate ?? DateTime(now.year + 30),
            );
            if (picked != null) onChanged(picked);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: BillyTheme.gray50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: BillyTheme.gray100),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: BillyTheme.gray500),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value == null ? 'Pick a date (optional)' : _fmt(value!),
                    style: TextStyle(
                      fontSize: 14,
                      color: value == null
                          ? BillyTheme.gray400
                          : BillyTheme.gray800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (value != null)
                  InkWell(
                    onTap: () => onChanged(null),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: BillyTheme.gray400),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper!,
            style: const TextStyle(
              fontSize: 11.5,
              color: BillyTheme.gray500,
            ),
          ),
        ],
      ],
    );
  }

  static String _fmt(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

/// Primary action button used at the footer of every setup sheet.
/// Shows a subtle spinner when `saving` is true.
class GoatPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool saving;
  final IconData? icon;

  const GoatPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.saving = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !saving;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: BillyTheme.emerald600,
          disabledBackgroundColor: BillyTheme.emerald100,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: saving
              ? const SizedBox(
                  key: ValueKey('saving'),
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  key: const ValueKey('label'),
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Tiny section header inside a sheet ("Income", "Safety net", "Preferences").
class GoatFormSectionHeader extends StatelessWidget {
  final String text;
  const GoatFormSectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: BillyTheme.gray500,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: BillyTheme.gray700,
        letterSpacing: -0.1,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// shared validators
// ──────────────────────────────────────────────────────────────────────────

String? goatValidateRequiredText(String? v, {String fieldLabel = 'This'}) {
  if (v == null || v.trim().isEmpty) return '$fieldLabel is required';
  return null;
}

String? goatValidatePositiveAmount(
  String? v, {
  bool required = true,
  double? max,
}) {
  if (v == null || v.trim().isEmpty) return required ? 'Enter an amount' : null;
  final d = double.tryParse(v.trim());
  if (d == null) return 'Enter a number';
  if (d <= 0) return 'Must be greater than 0';
  if (max != null && d > max) return 'Too large';
  return null;
}

String? goatValidateNonNegativeAmount(
  String? v, {
  bool required = false,
  double? max,
}) {
  if (v == null || v.trim().isEmpty) return required ? 'Enter a number' : null;
  final d = double.tryParse(v.trim());
  if (d == null) return 'Enter a number';
  if (d < 0) return "Can't be negative";
  if (max != null && d > max) return 'Too large';
  return null;
}

String? goatValidateIntRange(
  String? v, {
  required int min,
  required int max,
  bool required = false,
}) {
  if (v == null || v.trim().isEmpty) return required ? 'Enter a number' : null;
  final i = int.tryParse(v.trim());
  if (i == null) return 'Enter a whole number';
  if (i < min || i > max) return 'Must be between $min and $max';
  return null;
}
