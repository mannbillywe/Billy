import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

class QuickActions extends StatelessWidget {
  const QuickActions({
    super.key,
    this.onCreateBill,
    this.onOpenAllDocuments,
    this.onExportData,
  });

  final VoidCallback? onCreateBill;
  final VoidCallback? onOpenAllDocuments;
  final VoidCallback? onExportData;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _QuickAction(icon: Icons.add_rounded, label: 'Add', color: BillyTheme.emerald600, bg: BillyTheme.emerald50, onTap: onCreateBill),
        const SizedBox(width: 10),
        _QuickAction(icon: Icons.receipt_long_outlined, label: 'Docs', color: BillyTheme.blue400, bg: const Color(0xFFEFF6FF), onTap: onOpenAllDocuments),
        const SizedBox(width: 10),
        _QuickAction(icon: Icons.ios_share_rounded, label: 'Export', color: const Color(0xFFD97706), bg: const Color(0xFFFEF3C7), onTap: onExportData),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.color, required this.bg, this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BillyTheme.gray100),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(height: 8),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BillyTheme.gray700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
