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
    Icons.timeline_rounded,
    Icons.people_rounded,
    Icons.calendar_month_rounded,
    Icons.insights_rounded,
  ];

  static const _labels = ['Home', 'Activity', 'People', 'Plan', 'Insights'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: BillyTheme.gray100)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  _navItem(0),
                  _navItem(1),
                  const SizedBox(width: 64),
                  _navItem(3),
                  _navItem(4),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                top: -24,
                child: Center(
                  child: GestureDetector(
                    onTap: onFabTap,
                    child: Container(
                      width: 52,
                      height: 52,
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
                      child: const Icon(Icons.camera_alt_rounded, size: 24, color: Colors.white),
                    ),
                  ),
                ),
              ),
              // "People" (index 2) sits behind the FAB as a tap target
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                top: 0,
                child: Center(
                  child: SizedBox(
                    width: 64,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => onTap(2),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _labels[2],
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                color: activeIndex == 2 ? BillyTheme.emerald600 : BillyTheme.gray400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index) {
    final isActive = activeIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _icons[index],
                size: 22,
                color: isActive ? BillyTheme.emerald600 : BillyTheme.gray400,
              ),
              const SizedBox(height: 3),
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
      ),
    );
  }
}
