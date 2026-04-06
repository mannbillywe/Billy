import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/goat_theme.dart';
import '../../../providers/profile_provider.dart';
import '../../../services/supabase_service.dart';
import '../goat_profile.dart';
import '../widgets/goat_premium_card.dart';

class GoatPreferencesScreen extends ConsumerStatefulWidget {
  const GoatPreferencesScreen({super.key});

  @override
  ConsumerState<GoatPreferencesScreen> createState() => _GoatPreferencesScreenState();
}

class _GoatPreferencesScreenState extends ConsumerState<GoatPreferencesScreen> {
  bool _saving = false;

  Future<void> _setGoat(bool on) async {
    setState(() => _saving = true);
    try {
      await SupabaseService.setGoatAccess(on);
      ref.invalidate(profileProvider);
      if (!mounted) return;
      if (!on) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GOAT workspace disabled. Returning to Billy…')),
        );
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.valueOrNull;
    final goatOn = parseProfileGoatAccess(profile);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GOAT preferences',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: GoatTokens.textPrimary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Workspace access and defaults',
            style: TextStyle(color: GoatTokens.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          GoatPremiumCard(
            accentBorder: false,
            child: profileAsync.isLoading && profile == null
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
                  )
                : SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'GOAT workspace',
                      style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      goatOn
                          ? 'Recurring bills, forecast, and this shell are available. Turn off to hide GOAT from Billy home.'
                          : 'Off — turn on here or use “Enable GOAT for my account” if you were locked out.',
                      style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.35),
                    ),
                    value: goatOn,
                    onChanged: _saving ? null : _setGoat,
                    activeThumbColor: GoatTokens.gold,
                  ),
          ),
          const SizedBox(height: 16),
          GoatPremiumCard(
            accentBorder: false,
            child: Text(
              'More options (notifications, forecast defaults) can be added here as you refine the product.',
              style: TextStyle(color: GoatTokens.textMuted, height: 1.45, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
