import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

class QuickActions extends StatelessWidget {
  const QuickActions({
    super.key,
    this.onCreateBill,
    this.onLinkBank,
    this.onExportData,
  });

  final VoidCallback? onCreateBill;
  final VoidCallback? onLinkBank;
  final VoidCallback? onExportData;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Links',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
        ),
        const SizedBox(height: 12),
        _QuickLinkTile(icon: Icons.description_outlined, label: 'Create Bill', onTap: onCreateBill),
        const SizedBox(height: 10),
        _QuickLinkTile(icon: Icons.home_outlined, label: 'Link Bank', onTap: onLinkBank),
        const SizedBox(height: 10),
        _QuickLinkTile(icon: Icons.send_outlined, label: 'Export Data', onTap: onExportData),
      ],
    );
  }
}

class _QuickLinkTile extends StatelessWidget {
  const _QuickLinkTile({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BillyTheme.gray50),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: BillyTheme.emerald50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: BillyTheme.emerald600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray700)),
            ),
            const Icon(Icons.chevron_right, size: 16, color: BillyTheme.gray400),
          ],
        ),
      ),
    );
  }
}
