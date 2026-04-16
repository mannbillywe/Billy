import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/billy_theme.dart';
import '../../providers/profile_provider.dart';

class BillyHeader extends ConsumerWidget {
  const BillyHeader({
    super.key,
    required this.onOpenSettings,
    required this.onOpenGoatMode,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenGoatMode;

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
          _GoatModeButton(onTap: onOpenGoatMode),
          const SizedBox(width: 8),
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

class _GoatModeButton extends StatefulWidget {
  const _GoatModeButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_GoatModeButton> createState() => _GoatModeButtonState();
}

class _GoatModeButtonState extends State<_GoatModeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedBuilder(
          animation: _shimmer,
          builder: (context, child) {
            return Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: const [
                    Color(0xFF059669),
                    Color(0xFF10B981),
                    Color(0xFF34D399),
                    Color(0xFF10B981),
                    Color(0xFF059669),
                  ],
                  stops: [
                    0.0,
                    (_shimmer.value - 0.1).clamp(0.0, 1.0),
                    _shimmer.value,
                    (_shimmer.value + 0.1).clamp(0.0, 1.0),
                    1.0,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF059669).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.rocket_launch_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  const Text(
                    'GOAT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
