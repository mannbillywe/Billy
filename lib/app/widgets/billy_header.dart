import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/billy_theme.dart';
import '../../providers/profile_provider.dart';

class BillyHeader extends ConsumerWidget {
  const BillyHeader({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final displayName = profile?['display_name'] as String?;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: BillyTheme.scaffoldBg,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/branding/billy_logo.png',
              height: 48,
              width: 48,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: BillyTheme.emerald100,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text('B', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: BillyTheme.emerald600)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back!',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: BillyTheme.gray500,
                  ),
                ),
                Text(
                  displayName ?? 'Billy',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: BillyTheme.gray800,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpenSettings,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: BillyTheme.gray100,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.settings_outlined, size: 22, color: BillyTheme.gray600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
