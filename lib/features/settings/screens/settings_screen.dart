import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/profile_provider.dart';
import '../../../services/supabase_service.dart';
import '../../profile/screens/profile_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _currencies = ['USD', 'EUR', 'GBP', 'INR', 'JPY', 'CAD', 'AUD'];

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.valueOrNull;
    final currency = profile?['preferred_currency'] as String? ?? 'USD';

    final user = Supabase.instance.client.auth.currentUser;
    final displayName = profile?['display_name'] as String? ??
        user?.userMetadata?['full_name'] as String? ??
        user?.email?.split('@').first ??
        'User';
    final avatarUrl = profile?['avatar_url'] as String?;
    final initials = _buildInitials(displayName);

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: BillyTheme.scaffoldBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700, color: BillyTheme.gray800),
        ),
        iconTheme: const IconThemeData(color: BillyTheme.gray800),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          children: [
            const SizedBox(height: 8),

            // ── Avatar ──
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: BillyTheme.emerald100,
                    backgroundImage:
                        avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null || avatarUrl.isEmpty
                        ? Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: BillyTheme.emerald600,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => _showComingSoon('Avatar upload'),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.camera_alt_rounded, size: 14, color: BillyTheme.gray500),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Display name ──
            Text(
              displayName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: BillyTheme.gray800,
              ),
            ),

            const SizedBox(height: 8),

            // ── Badge pill ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: BillyTheme.emerald50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'BILLY USER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: BillyTheme.emerald600,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── ACCOUNT SETTINGS ──
            _sectionHeader('ACCOUNT SETTINGS'),
            const SizedBox(height: 10),
            _settingsGroup([
              _settingsRow(
                icon: Icons.person_outline,
                title: 'Personal Information',
                subtitle: 'Name, email, and phone',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
                  );
                },
              ),
              _settingsRow(
                icon: Icons.credit_card_outlined,
                title: 'Payment Methods',
                subtitle: 'Connected banks and cards',
                onTap: () => _showComingSoon('Payment Methods'),
              ),
            ]),

            const SizedBox(height: 24),

            // ── SYSTEM & PRIVACY ──
            _sectionHeader('SYSTEM & PRIVACY'),
            const SizedBox(height: 10),
            _settingsGroup([
              _settingsRow(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: 'Manage alerts and news',
                onTap: () => _showComingSoon('Notifications'),
              ),
              _settingsRow(
                icon: Icons.shield_outlined,
                title: 'Security',
                subtitle: 'Biometrics and 2FA',
                onTap: () => _showComingSoon('Security'),
              ),
              _settingsRow(
                icon: Icons.language_rounded,
                title: 'Preferences',
                subtitle: 'Language and currency',
                onTap: () => _showCurrencyPicker(currency),
              ),
            ]),

            const SizedBox(height: 24),

            // ── HELP & LEGAL ──
            _sectionHeader('HELP & LEGAL'),
            const SizedBox(height: 10),
            _settingsGroup([
              _settingsRow(
                icon: Icons.help_outline_rounded,
                title: 'Support Center',
                subtitle: 'FAQs and contact us',
                onTap: () => _showComingSoon('Support Center'),
              ),
            ]),

            const SizedBox(height: 32),

            // ── Sign Out ──
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                },
                style: TextButton.styleFrom(
                  backgroundColor: BillyTheme.emerald50,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  'Sign Out',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Version ──
            const Text(
              'VERSION 1.0.0',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
                color: BillyTheme.gray400,
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming soon'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _buildInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Widget _sectionHeader(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: BillyTheme.gray400,
          ),
        ),
      ),
    );
  }

  Widget _settingsGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, thickness: 1, color: BillyTheme.gray100, indent: 68, endIndent: 16),
          ],
        ],
      ),
    );
  }

  Widget _settingsRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: BillyTheme.emerald50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: BillyTheme.emerald600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: BillyTheme.gray800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: BillyTheme.gray500),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: BillyTheme.gray400),
          ],
        ),
      ),
    );
  }

  void _showCurrencyPicker(String currentCurrency) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: BillyTheme.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Display Currency',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Used for amounts across the app',
                style: TextStyle(fontSize: 13, color: BillyTheme.gray500),
              ),
              const SizedBox(height: 16),
              ..._currencies.map((c) {
                final selected = c == currentCurrency;
                return ListTile(
                  title: Text(
                    c,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? BillyTheme.emerald600 : BillyTheme.gray800,
                    ),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_rounded, color: BillyTheme.emerald600)
                      : null,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    if (c == currentCurrency) return;
                    await SupabaseService.updateProfile(preferredCurrency: c);
                    ref.invalidate(profileProvider);
                    if (mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Currency set to $c')));
                    }
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
