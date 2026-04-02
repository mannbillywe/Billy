import 'package:flutter/material.dart';

import '../../core/theme/billy_theme.dart';

class BillyHeader extends StatelessWidget {
  const BillyHeader({super.key});

  @override
  Widget build(BuildContext context) {
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
              errorBuilder: (_, __, ___) => Container(
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
                  'Billy',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: BillyTheme.gray800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
