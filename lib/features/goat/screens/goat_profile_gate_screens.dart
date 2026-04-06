import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/telemetry/goat_telemetry.dart';
import '../../../core/theme/goat_theme.dart';
import '../../../providers/profile_provider.dart';
import '../../../services/supabase_service.dart';

/// [profileProvider] failed (network, RLS, etc.) — do not treat as "GOAT locked".
class GoatProfileLoadErrorScreen extends ConsumerWidget {
  const GoatProfileLoadErrorScreen({
    super.key,
    required this.onBack,
    this.detail,
  });

  final VoidCallback onBack;
  final String? detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Icon(Icons.wifi_off_rounded, size: 56, color: GoatTokens.gold.withValues(alpha: 0.85)),
                const SizedBox(height: 20),
                Text(
                  'Could not verify account',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: GoatTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Something went wrong while loading your profile. Retry, or go back to Billy.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GoatTokens.textMuted, height: 1.45, fontSize: 14),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    detail!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: GoatTokens.textMuted.withValues(alpha: 0.8), fontSize: 11, height: 1.35),
                  ),
                ],
                const Spacer(),
                FilledButton(
                  onPressed: () => ref.invalidate(profileProvider),
                  style: FilledButton.styleFrom(
                    backgroundColor: GoatTokens.gold,
                    foregroundColor: GoatTokens.background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 10),
                TextButton(onPressed: onBack, child: const Text('Back to Billy')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Profile row missing or fetch returned null — retry instead of showing a false "locked" state.
class GoatProfileMissingScreen extends ConsumerWidget {
  const GoatProfileMissingScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Icon(Icons.cloud_off_outlined, size: 56, color: GoatTokens.gold.withValues(alpha: 0.85)),
                const SizedBox(height: 20),
                Text(
                  'Profile not loaded',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: GoatTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'We could not load your account profile from the server. Check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GoatTokens.textMuted, height: 1.45, fontSize: 14),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    ref.invalidate(profileProvider);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: GoatTokens.gold,
                    foregroundColor: GoatTokens.background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 10),
                TextButton(onPressed: onBack, child: const Text('Back to Billy')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GoatAccessDeniedScreen extends ConsumerStatefulWidget {
  const GoatAccessDeniedScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<GoatAccessDeniedScreen> createState() => _GoatAccessDeniedScreenState();
}

class _GoatAccessDeniedScreenState extends ConsumerState<GoatAccessDeniedScreen> {
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      logGoatEvent('goat_locked_access_attempt');
    });
  }

  Future<void> _enableForMe() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await SupabaseService.setGoatAccess(true);
      ref.invalidate(profileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GOAT workspace enabled. Loading…')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _err = '$e');
      }
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
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Icon(Icons.lock_outline_rounded, size: 56, color: GoatTokens.gold.withValues(alpha: 0.85)),
                const SizedBox(height: 20),
                Text(
                  'GOAT Mode',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: GoatTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This workspace is turned off for your account. You can enable it below, or ask your Billy operator if your organization manages access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GoatTokens.textMuted, height: 1.45, fontSize: 14),
                ),
                if (_err != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _err!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12, height: 1.35),
                  ),
                ],
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _enableForMe,
                  style: FilledButton.styleFrom(
                    backgroundColor: GoatTokens.gold,
                    foregroundColor: GoatTokens.background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A0A0B)),
                        )
                      : const Text('Enable GOAT for my account', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: widget.onBack,
                  child: const Text('Return to Billy'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
