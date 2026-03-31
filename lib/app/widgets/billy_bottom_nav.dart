import 'package:flutter/material.dart';

import '../../core/theme/billy_theme.dart';

class BillyBottomNav extends StatelessWidget {
  const BillyBottomNav({
    super.key,
    required this.activeIndex,
    required this.onTap,
    this.onFabTap,
  });

  final int activeIndex;
  final ValueChanged<int> onTap;
  final VoidCallback? onFabTap;

  static const _icons = [
    Icons.home_rounded,
    Icons.bar_chart_rounded,
    Icons.people_rounded,
    Icons.settings_rounded,
  ];

  static const _labels = ['Home', 'Analytics', 'Friends', 'Settings'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: BillyTheme.gray100)),
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ..._buildNavItems(0, 2),
                  const SizedBox(width: 56),
                  ..._buildNavItems(2, 4),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: -28,
              child: Center(
                child: GestureDetector(
                  onTap: onFabTap,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: BillyTheme.emerald600,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: BillyTheme.emerald600.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add, size: 28, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildNavItems(int start, int end) {
    return List.generate(end - start, (i) {
      final index = start + i;
      final isActive = activeIndex == index;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(index),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _icons[index],
                size: 24,
                color: isActive ? BillyTheme.emerald600 : BillyTheme.gray400,
              ),
              const SizedBox(height: 4),
              Text(
                _labels[index],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isActive ? BillyTheme.emerald600 : BillyTheme.gray400,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
