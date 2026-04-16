import 'package:flutter/material.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';

class RecentActivityItem {
  const RecentActivityItem({
    this.documentId,
    required this.vendor,
    required this.amount,
    required this.category,
    required this.date,
    required this.icon,
    this.backdateHint,
  });

  final String? documentId;
  final String vendor;
  final double amount;
  final String category;
  final String date;
  final String icon;

  /// Shown when invoice [date] is before save day (see [DocumentBackdateHint]).
  final String? backdateHint;
}

class RecentActivity extends StatelessWidget {
  const RecentActivity({
    super.key,
    required this.items,
    this.currencyCode,
    this.onItemTap,
  });

  final List<RecentActivityItem> items;
  final String? currencyCode;
  final void Function(String documentId)? onItemTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BillyTheme.gray100),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final id = item.documentId;
          final tappable = onItemTap != null && id != null && id.isNotEmpty;
          final isLast = index == items.length - 1;

          return Material(
            color: Colors.white,
            child: InkWell(
              onTap: tappable ? () => onItemTap!(id) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: isLast
                    ? null
                    : const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: BillyTheme.gray100, width: 1),
                        ),
                      ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: BillyTheme.emerald50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        item.icon,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: BillyTheme.emerald600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.vendor,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: BillyTheme.gray800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: BillyTheme.gray100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.category,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: BillyTheme.gray600,
                                  ),
                                ),
                              ),
                              if (item.backdateHint != null &&
                                  item.backdateHint!.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  item.backdateHint!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFC2410C),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\u2212${AppCurrency.format(item.amount, currencyCode)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: BillyTheme.gray800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.date,
                          style: const TextStyle(
                            fontSize: 11,
                            color: BillyTheme.gray500,
                          ),
                        ),
                      ],
                    ),
                    if (tappable) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        color: BillyTheme.gray400,
                        size: 20,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
