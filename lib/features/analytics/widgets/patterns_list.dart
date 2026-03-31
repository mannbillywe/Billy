import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

class PatternItem {
  const PatternItem({required this.emoji, required this.title, required this.subtitle});
  final String emoji;
  final String title;
  final String subtitle;
}

class PatternsList extends StatelessWidget {
  const PatternsList({super.key, required this.patterns});
  final List<PatternItem> patterns;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: patterns.map((p) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BillyTheme.gray50),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: BillyTheme.emerald50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(p.emoji, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
                      const SizedBox(height: 2),
                      Text(p.subtitle, style: const TextStyle(fontSize: 12, color: BillyTheme.gray500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
