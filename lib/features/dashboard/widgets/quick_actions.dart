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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FINANCIAL COMMAND CENTER',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: BillyTheme.gray500,
          ),
        ),
        const SizedBox(height: 12),
        // Instant Scan — primary action card
        _CommandCard(
          icon: Icons.camera_alt_rounded,
          iconBg: BillyTheme.emerald600,
          iconColor: Colors.white,
          title: 'Instant Scan',
          subtitle: 'Capture receipts & invoices instantly',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Launch Camera',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BillyTheme.emerald600,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: BillyTheme.emerald600,
              ),
            ],
          ),
          onTap: onCreateBill,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _CommandCardCompact(
                icon: Icons.folder_open_rounded,
                iconBg: const Color(0xFFEFF6FF),
                iconColor: BillyTheme.blue400,
                title: 'All Documents',
                subtitle: 'Browse & manage',
                onTap: onOpenAllDocuments,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CommandCardCompact(
                icon: Icons.ios_share_rounded,
                iconBg: const Color(0xFFFEF3C7),
                iconColor: const Color(0xFFD97706),
                title: 'Export',
                subtitle: 'CSV / PDF',
                onTap: onExportData,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Full-width action card with icon, title, subtitle, and trailing widget.
class _CommandCard extends StatelessWidget {
  const _CommandCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: BillyTheme.gray100),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: BillyTheme.gray800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: BillyTheme.gray500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact two-column action card.
class _CommandCardCompact extends StatelessWidget {
  const _CommandCardCompact({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: BillyTheme.gray100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: BillyTheme.gray800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: BillyTheme.gray500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
