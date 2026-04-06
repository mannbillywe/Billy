import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/goat_theme.dart';
import '../../../providers/goat_cash_providers.dart';
import '../../../providers/profile_provider.dart';
import '../recurring/add_recurring_sheet.dart';
import '../recurring/recurring_repository.dart';
import '../widgets/goat_premium_card.dart';

class GoatRecurringScreen extends ConsumerWidget {
  const GoatRecurringScreen({super.key});

  static String _statusLabel(String? s) {
    switch (s) {
      case 'active':
        return 'Active';
      case 'paused':
        return 'Paused';
      case 'suggested':
        return 'Suggested';
      case 'cancelled':
        return 'Cancelled';
      default:
        return s ?? '—';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.watch(goatRecurringBundleProvider);
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR';

    return bundle.when(
      loading: () => const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load recurring data.\n\nIf this is the first time, apply the latest Supabase migration for recurring tables.\n\n$e',
            style: TextStyle(color: GoatTokens.textMuted, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (b) {
        final series = b.series;
        final occ = b.occ.where((o) => o['status'] == 'upcoming' || o['status'] == 'overdue').take(12).toList();

        return Stack(
          children: [
            RefreshIndicator(
              color: GoatTokens.gold,
              onRefresh: () => ref.read(goatRecurringBundleProvider.notifier).reload(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                      Text(
                        'Recurring',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: GoatTokens.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Bills & subscriptions (deterministic due dates)',
                        style: TextStyle(color: GoatTokens.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      if (series.isEmpty && occ.isEmpty)
                        GoatPremiumCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'No recurring items yet',
                                style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add rent, subscriptions, or EMIs. Forecast uses these for upcoming outflows.',
                                style: TextStyle(color: GoatTokens.textMuted, height: 1.45, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      if (occ.isNotEmpty) ...[
                        Text(
                          'Upcoming dues',
                          style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                        ...occ.map(
                          (o) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GoatPremiumCard(
                              accentBorder: false,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          o['due_date']?.toString() ?? '—',
                                          style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w600, fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Occurrence · ${o['status']}',
                                          style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    AppCurrency.format((o['expected_amount'] as num?)?.toDouble() ?? 0, currency),
                                    style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        'All series',
                        style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      ...series.map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GoatPremiumCard(
                            accentBorder: false,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        s['title']?.toString() ?? '—',
                                        style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: GoatTokens.surfaceElevated,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: GoatTokens.borderSubtle),
                                      ),
                                      child: Text(
                                        _statusLabel(s['status'] as String?),
                                        style: TextStyle(fontSize: 10, color: GoatTokens.textMuted, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${s['frequency']} · next ${s['next_due_date'] ?? '—'}',
                                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppCurrency.format((s['expected_amount'] as num?)?.toDouble() ?? 0, currency),
                                  style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w800, fontSize: 16),
                                ),
                                if ((s['status'] as String?) == 'active') ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: () async {
                                          await RecurringRepository.pauseSeries(s['id'] as String);
                                          ref.invalidate(goatRecurringBundleProvider);
                                          ref.invalidate(goatForecastProvider);
                                        },
                                        child: const Text('Pause'),
                                      ),
                                    ],
                                  ),
                                ],
                                if ((s['status'] as String?) == 'paused')
                                  TextButton(
                                    onPressed: () async {
                                      await RecurringRepository.resumeSeries(s['id'] as String);
                                      ref.invalidate(goatRecurringBundleProvider);
                                      ref.invalidate(goatForecastProvider);
                                    },
                                    child: const Text('Resume'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () async {
                  final ok = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: GoatTokens.surface,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (ctx) => const AddRecurringSheet(),
                  );
                  if (ok == true) {
                    ref.invalidate(goatRecurringBundleProvider);
                    ref.invalidate(goatForecastProvider);
                  }
                },
                backgroundColor: GoatTokens.gold.withValues(alpha: 0.2),
                foregroundColor: GoatTokens.gold,
                icon: const Icon(Icons.add),
                label: const Text('Add recurring'),
              ),
            ),
          ],
        );
      },
    );
  }
}
