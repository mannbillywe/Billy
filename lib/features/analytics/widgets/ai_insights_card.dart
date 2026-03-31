import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

class AiInsightsCard extends StatelessWidget {
  const AiInsightsCard({
    super.key,
    required this.insights,
    required this.highlights,
  });

  final List<String> insights;
  final List<(String, bool)> highlights;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: BillyTheme.gray800,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: BillyTheme.gray300.withValues(alpha: 0.5), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: Opacity(opacity: 0.15, child: Icon(Icons.psychology_rounded, size: 60, color: Colors.white)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 18, color: BillyTheme.yellow400),
                  const SizedBox(width: 8),
                  Text('BILLY AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: BillyTheme.gray300)),
                ],
              ),
              const SizedBox(height: 20),
              ...insights.asMap().entries.map((e) {
                final i = e.key;
                final text = e.value;
                final highlight = i < highlights.length ? highlights[i] : null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInsightText(text, highlight),
                    if (i < insights.length - 1) ...[
                      const SizedBox(height: 16),
                      Container(height: 1, color: BillyTheme.gray700),
                      const SizedBox(height: 16),
                    ],
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInsightText(String text, (String, bool)? highlight) {
    if (highlight == null || !text.contains(highlight.$1)) {
      return Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white, height: 1.4));
    }

    final idx = text.indexOf(highlight.$1);
    final before = text.substring(0, idx);
    final after = text.substring(idx + highlight.$1.length);

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white, height: 1.4),
        children: [
          TextSpan(text: before),
          TextSpan(text: highlight.$1, style: TextStyle(fontWeight: FontWeight.w700, color: highlight.$2 ? BillyTheme.yellow400 : BillyTheme.red400)),
          TextSpan(text: after),
        ],
      ),
    );
  }
}
