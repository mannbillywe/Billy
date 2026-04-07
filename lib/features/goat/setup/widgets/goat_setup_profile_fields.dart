import 'package:flutter/material.dart';

import '../../../../core/theme/goat_theme.dart';

class GoatSetupProfileFields extends StatefulWidget {
  const GoatSetupProfileFields({super.key, required this.initial, required this.onChanged});

  final Map<String, dynamic> initial;
  final void Function(Map<String, dynamic>) onChanged;

  @override
  State<GoatSetupProfileFields> createState() => _GoatSetupProfileFieldsState();
}

class _GoatSetupProfileFieldsState extends State<GoatSetupProfileFields> {
  late TextEditingController _cur;
  late TextEditingController _lens;

  @override
  void initState() {
    super.initState();
    _cur = TextEditingController(text: widget.initial['preferred_currency']?.toString() ?? '');
    _lens = TextEditingController(text: widget.initial['goat_analysis_lens']?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant GoatSetupProfileFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial['preferred_currency'] != widget.initial['preferred_currency']) {
      _cur.text = widget.initial['preferred_currency']?.toString() ?? '';
    }
    if (oldWidget.initial['goat_analysis_lens'] != widget.initial['goat_analysis_lens']) {
      _lens.text = widget.initial['goat_analysis_lens']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _cur.dispose();
    _lens.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged({
      'preferred_currency': _cur.text.trim().isEmpty ? null : _cur.text.trim(),
      'goat_analysis_lens': _lens.text.trim().isEmpty ? null : _lens.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _cur,
          style: const TextStyle(color: GoatTokens.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Preferred currency',
            labelStyle: TextStyle(color: GoatTokens.textMuted),
          ),
          onChanged: (_) => _emit(),
        ),
        TextField(
          controller: _lens,
          style: const TextStyle(color: GoatTokens.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Analysis lens (smart, statements_only, ocr_only, combined_raw)',
            labelStyle: TextStyle(color: GoatTokens.textMuted),
          ),
          onChanged: (_) => _emit(),
        ),
      ],
    );
  }
}
