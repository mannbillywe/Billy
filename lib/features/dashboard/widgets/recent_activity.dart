import 'package:flutter/material.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';

class RecentActivityItem {
  const RecentActivityItem({
    required this.vendor,
    required this.amount,
    required this.category,
    required this.date,
    required this.icon,
  });

  final String vendor;
  final double amount;
  final String category;
  final String date;
  final String icon;
}

class RecentActivity extends StatelessWidget {
  const RecentActivity({super.key, required this.items, this.currencyCode});

  final List<RecentActivityItem> items;
  final String? currencyCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BillyTheme.gray50),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
              ],
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
                  child: Text(
                    item.icon,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BillyTheme.emerald600),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.vendor,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.category} \u2022 ${item.date}',
                        style: const TextStyle(fontSize: 12, color: BillyTheme.gray500),
                      ),
                    ],
                  ),
                ),
                Text(
                  '-${AppCurrency.format(item.amount, currencyCode)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
