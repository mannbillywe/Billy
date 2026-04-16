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
    final showGoat = profileGoatModeEnabled(profile);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: BillyTheme.scaffoldBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 400;
          return Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/branding/billy_logo.png',
                  height: 44,
                  width: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: BillyTheme.emerald100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Text('B', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: BillyTheme.emerald600)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Welcome back!',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: BillyTheme.gray500,
                      ),
                    ),
                    Text(
                      displayName ?? 'Billy',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: BillyTheme.gray800,
                      ),
                    ),
                  ],
                ),
              ),
              if (showGoat) ...[
                const SizedBox(width: 6),
                _GoatModeButton(onTap: onOpenGoatMode, compact: narrow),
              ],
              const SizedBox(width: 6),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onOpenSettings,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: BillyTheme.gray100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: BillyTheme.gray200.withValues(alpha: 0.6)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.settings_outlined, size: 22, color: BillyTheme.gray600),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GoatModeButton extends StatefulWidget {
  const _GoatModeButton({required this.onTap, required this.compact});
  final VoidCallback onTap;
  final bool compact;

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
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  /// Animate gradient direction only — [LinearGradient.stops] must stay strictly
  /// increasing; the old shimmer used duplicate stops at 0 and broke painting.
  BoxDecoration _decoration(double t) {
    final begin = Alignment(-1.4 + t * 1.1, -0.35);
    final end = Alignment(-0.2 + t * 1.1, 0.45);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: begin,
        end: end,
        colors: const [
          Color(0xFF047857),
          Color(0xFF059669),
          Color(0xFF10B981),
          Color(0xFF34D399),
        ],
        stops: const [0.0, 0.35, 0.65, 1.0],
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF059669).withValues(alpha: 0.35),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'GOAT Mode — AI features (preview)',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedBuilder(
            animation: _shimmer,
            builder: (context, child) {
              final t = Curves.easeInOut.transform(
                _shimmer.value <= 0.5 ? _shimmer.value * 2 : (1 - _shimmer.value) * 2,
              );
              if (widget.compact) {
                return Semantics(
                  button: true,
                  label: 'GOAT Mode',
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: _decoration(t),
                    alignment: Alignment.center,
                    child: const Icon(Icons.rocket_launch_rounded, size: 22, color: Colors.white),
                  ),
                );
              }
              return Semantics(
                button: true,
                label: 'GOAT Mode',
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: _decoration(t),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'GOAT Mode',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
