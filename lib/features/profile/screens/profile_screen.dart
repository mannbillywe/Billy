import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../export/models/export_document.dart';
import '../../export/screens/export_screen.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../goat/goat_profile.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authStateProvider);
    final user = authAsync.valueOrNull;
    final docsAsync = ref.watch(documentsProvider);
    final docs = docsAsync.valueOrNull ?? [];
    final currency =
        ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR';

    final displayName = user?.userMetadata?['full_name'] as String? ?? user?.email?.split('@').first ?? 'User';
    final email = user?.email ?? '';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    final exportDocs = documentsForExport(docs);

    final totalDocs = docs.length;
    final totalSpend = docs
        .where((d) => (d['status'] as String?) != 'draft')
        .fold<double>(0, (s, d) => s + ((d['amount'] as num?)?.toDouble() ?? 0));
    final profileRow = ref.watch(profileProvider).valueOrNull;
    final goatEnabled = parseProfileGoatAccess(profileRow);

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: BillyTheme.scaffoldBg,
        elevation: 0,
        title: const Text('Account', style: TextStyle(color: BillyTheme.gray800, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: BillyTheme.gray800),
      ),
      body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Profile', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: BillyTheme.emerald600,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(initial, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                    const SizedBox(height: 4),
                    Text(email, style: const TextStyle(fontSize: 14, color: BillyTheme.gray500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _StatBox(value: '$totalDocs', label: 'RECEIPTS'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBox(
                  value: AppCurrency.formatCompact(totalSpend, currency),
                  label: 'TOTAL SPEND',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
          const SizedBox(height: 12),
          _SettingsTile(
            label: 'GOAT access',
            subtitle: goatEnabled
                ? 'On — open from Home (card or header) for Recurring & Forecast'
                : 'Off — open GOAT once and tap “Enable GOAT for my account”, or use GOAT → Prefs',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    goatEnabled
                        ? 'Open GOAT from the Home tab (dark card) or the GOAT chip in the header.'
                        : 'From Billy: open GOAT (if you see the lock screen, enable there). Inside GOAT, use Prefs to turn the workspace on or off.',
                  ),
                ),
              );
            },
          ),
          _SettingsTile(
            label: 'Notifications',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'In-app notification settings are not available yet. Use your device Settings to control alerts for Billy.',
                  ),
                ),
              );
            },
          ),
          _SettingsTile(label: 'Export Data', onTap: () {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExportScreen(documents: exportDocs)));
          }),
          _SettingsTile(
            label: 'Privacy Policy',
            onTap: () => _showPrivacyPolicy(context),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => Supabase.instance.client.auth.signOut(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: BillyTheme.gray100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.logout_rounded, size: 20, color: BillyTheme.gray800),
                  SizedBox(width: 10),
                  Text('Log Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Privacy'),
        content: const SingleChildScrollView(
          child: Text(
            'Billy stores your account and receipt data in the database for your project (for example Supabase), under that provider’s terms and your configuration. '
            'Sign-in and third-party APIs are only used as you set up in the app. You can export your documents from Export Data. '
            'For questions about your data, contact whoever operates this Billy deployment.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BillyTheme.gray500)),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.label, required this.onTap, this.subtitle});
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BillyTheme.gray100),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray800)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: const TextStyle(fontSize: 12, color: BillyTheme.gray500, height: 1.3)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: BillyTheme.gray400),
          ],
        ),
      ),
    );
  }
}
