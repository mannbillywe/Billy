import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../export/models/export_document.dart';
import '../../export/screens/export_screen.dart';
import '../../../providers/documents_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  void _showApiKeyDialog() async {
    final key = await SupabaseService.getGeminiApiKey();
    if (!mounted) return;
    final ctrl = TextEditingController(text: key ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Gemini API Key', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Use your own Google AI key for receipt extraction.', style: TextStyle(fontSize: 14, color: BillyTheme.gray500)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'AIza...',
                filled: true,
                fillColor: BillyTheme.gray50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BillyTheme.emerald600)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final val = ctrl.text.trim();
              await SupabaseService.updateProfile(geminiApiKey: val.isEmpty ? '' : val);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Save', style: TextStyle(color: BillyTheme.emerald600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authStateProvider);
    final user = authAsync.valueOrNull;
    final docsAsync = ref.watch(documentsProvider);
    final docs = docsAsync.valueOrNull ?? [];

    final displayName = user?.userMetadata?['full_name'] as String? ?? user?.email?.split('@').first ?? 'User';
    final email = user?.email ?? '';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    final exportDocs = docs.map((d) => ExportDocument(
      vendorName: d['vendor_name'] as String? ?? '',
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      date: DateTime.tryParse(d['date'] as String? ?? '') ?? DateTime.now(),
      category: (d['description'] as String?)?.split(',').first.trim() ?? 'Other',
      type: d['type'] as String? ?? 'receipt',
    )).toList();

    final totalDocs = docs.length;

    return SingleChildScrollView(
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
                  value: '\$${docs.fold(0.0, (sum, d) => sum + ((d['amount'] as num?)?.toDouble() ?? 0)) > 1000 ? '${(docs.fold(0.0, (sum, d) => sum + ((d['amount'] as num?)?.toDouble() ?? 0)) / 1000).toStringAsFixed(1)}k' : docs.fold(0.0, (sum, d) => sum + ((d['amount'] as num?)?.toDouble() ?? 0)).toStringAsFixed(0)}',
                  label: 'TOTAL SPEND',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
          const SizedBox(height: 12),
          _SettingsTile(label: 'Notifications', onTap: () {}),
          _SettingsTile(label: 'Gemini API Key', onTap: _showApiKeyDialog),
          _SettingsTile(label: 'Export Data', onTap: () {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExportScreen(documents: exportDocs)));
          }),
          _SettingsTile(label: 'Privacy Policy', onTap: () {}),
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
  const _SettingsTile({required this.label, required this.onTap});
  final String label;
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
          children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray800)),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, size: 20, color: BillyTheme.gray400),
          ],
        ),
      ),
    );
  }
}
