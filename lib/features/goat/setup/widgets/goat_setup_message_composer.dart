import 'package:flutter/material.dart';

import '../../../../core/theme/goat_theme.dart';

class GoatSetupMessageComposer extends StatefulWidget {
  const GoatSetupMessageComposer({
    super.key,
    required this.onSend,
    this.enabled = true,
    this.hintText = 'Describe your income, accounts, bills, goals…',
  });

  final Future<void> Function(String text) onSend;
  final bool enabled;
  final String hintText;

  @override
  State<GoatSetupMessageComposer> createState() => _GoatSetupMessageComposerState();
}

class _GoatSetupMessageComposerState extends State<GoatSetupMessageComposer> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = _controller.text.trim();
    if (t.isEmpty || !widget.enabled || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSend(t);
      if (mounted) _controller.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GoatTokens.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: widget.enabled && !_busy,
                minLines: 1,
                maxLines: 5,
                style: const TextStyle(color: GoatTokens.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: widget.hintText,
                  hintStyle: TextStyle(color: GoatTokens.textMuted.withValues(alpha: 0.85)),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            IconButton.filled(
              onPressed: (widget.enabled && !_busy) ? _submit : null,
              style: IconButton.styleFrom(
                backgroundColor: GoatTokens.gold.withValues(alpha: 0.2),
                foregroundColor: GoatTokens.gold,
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: GoatTokens.gold),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
