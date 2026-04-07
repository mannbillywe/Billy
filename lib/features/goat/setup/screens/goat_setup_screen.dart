import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/goat_theme.dart';
import '../goat_setup_applier.dart';
import '../goat_setup_providers.dart';
import '../goat_setup_repository.dart';
import 'goat_setup_chat_screen.dart';
import 'goat_setup_form_fallback_screen.dart';

/// Welcome + entry: chat-first, guided, form fallback, or later.
class GoatSetupScreen extends ConsumerStatefulWidget {
  const GoatSetupScreen({super.key});

  @override
  ConsumerState<GoatSetupScreen> createState() => _GoatSetupScreenState();
}

class _GoatSetupScreenState extends ConsumerState<GoatSetupScreen> {
  bool _busy = false;

  Future<void> _prime() async {
    setState(() => _busy = true);
    try {
      await GoatSetupRepository.ensureSetupState();
      await GoatSetupRepository.touchLastSeen();
      await GoatSetupRepository.updateSetupState(status: 'in_progress');
      ref.invalidate(goatSetupStateProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('GOAT setup'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tell Billy about your money life',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: GoatTokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Type naturally — GOAT turns it into structured accounts, income, bills, and goals. '
                'You review every value before anything is saved.',
                style: TextStyle(color: GoatTokens.textMuted, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                'Example: “I earn around ₹85k salary on the 1st, rent is ₹22k, one EMI ₹9k, two credit cards, and I want to save for travel.”',
                style: TextStyle(color: GoatTokens.textMuted.withValues(alpha: 0.9), fontSize: 12, height: 1.35, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 24),
              if (_busy) const LinearProgressIndicator(minHeight: 2, color: GoatTokens.gold),
              const SizedBox(height: 16),
              _chipButton(
                context,
                label: 'I want to type it myself',
                icon: Icons.edit_note_rounded,
                onTap: () async {
                  await _prime();
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const GoatSetupChatScreen(guidedOneAtATime: false)),
                  );
                },
              ),
              const SizedBox(height: 10),
              _chipButton(
                context,
                label: 'Ask me one thing at a time',
                icon: Icons.question_answer_outlined,
                onTap: () async {
                  await _prime();
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const GoatSetupChatScreen(guidedOneAtATime: true)),
                  );
                },
              ),
              const SizedBox(height: 10),
              _chipButton(
                context,
                label: 'Use forms instead',
                icon: Icons.view_list_rounded,
                onTap: () async {
                  await _prime();
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const GoatSetupFormFallbackScreen()),
                  );
                },
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await _prime();
                        await GoatSetupRepository.updateSetupState(status: 'skipped');
                        ref.invalidate(goatSetupStateProvider);
                        await GoatSetupApplier.syncReadinessToState();
                        ref.invalidate(goatReadinessProvider);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                child: Text('I’ll do this later', style: TextStyle(color: GoatTokens.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: GoatTokens.surfaceElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: GoatTokens.gold),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: GoatTokens.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
