import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/profile_provider.dart';
import '../../../services/supabase_service.dart';
import '../../export/models/export_document.dart';
import '../../export/screens/export_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../../providers/documents_provider.dart';

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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
          const SizedBox(height: 8),
          const Text(
            'Currency and account',
            style: TextStyle(fontSize: 14, color: BillyTheme.gray500),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BillyTheme.gray100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Display currency', style: TextStyle(fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
                const SizedBox(height: 8),
                const Text(
                  'Used for amounts across the app (does not convert stored values).',
                  style: TextStyle(fontSize: 12, color: BillyTheme.gray500),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _currencies.contains(currency) ? currency : 'USD',
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: _currencies
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    await SupabaseService.updateProfile(preferredCurrency: v);
                    ref.invalidate(profileProvider);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Currency set to $v')));
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _tile(
            icon: Icons.person_outline,
            title: 'Account',
            subtitle: 'Profile and sign out',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          _tile(
            icon: Icons.file_download_outlined,
            title: 'Export data',
            subtitle: 'PDF / CSV from your documents',
            onTap: () {
              final docs = ref.read(documentsProvider).valueOrNull ?? [];
              final exportDocs = documentsForExport(docs);
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => ExportScreen(documents: exportDocs)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: BillyTheme.gray100),
          ),
          leading: Icon(icon, color: BillyTheme.emerald600),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
