import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/goat_theme.dart';
import '../../../providers/goat_cash_providers.dart';
import '../../../providers/goat_goals_providers.dart';
import '../../../providers/goat_lens_provider.dart';
import '../../../providers/profile_provider.dart';
import '../finance/cashflow_engine.dart';
import '../finance/finance_repository.dart';
import '../widgets/goat_premium_card.dart';

class GoatForecastScreen extends ConsumerStatefulWidget {
  const GoatForecastScreen({super.key});

  @override
  ConsumerState<GoatForecastScreen> createState() => _GoatForecastScreenState();
}

class _GoatForecastScreenState extends ConsumerState<GoatForecastScreen> {
  final _reserveCtrl = TextEditingController();

  @override
  void dispose() {
    _reserveCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR';
    final analysisLens = ref.watch(goatAnalysisLensProvider);
    final horizon = ref.watch(goatForecastHorizonProvider);
    final forecast = ref.watch(goatForecastProvider);
    final goalsSummary = ref.watch(goatGoalsSummaryProvider);
    final reservePaise = ref.watch(forecastReserveProvider);
    final whatIfPaise = ref.watch(whatIfSpendTodayProvider);

    if (_reserveCtrl.text.isEmpty && reservePaise == 0) {
      _reserveCtrl.text = '';
    }

    return RefreshIndicator(
      color: GoatTokens.gold,
      onRefresh: () async {
        ref.invalidate(goatRecurringBundleProvider);
        ref.invalidate(financialAccountsProvider);
        ref.invalidate(incomeStreamsProvider);
        ref.invalidate(plannedCashEventsProvider);
        ref.invalidate(goatGoalsProvider);
        ref.invalidate(goatGoalsSummaryProvider);
        ref.invalidate(goatGoalsForecastInputProvider);
        ref.invalidate(goatForecastProvider);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'Forecast',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: GoatTokens.textPrimary,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Safe-to-spend & cash-flow (deterministic)',
                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  'Analysis lens: ${analysisLens.label} — modeled from accounts, recurring, income, planned events, and goal hard-reserve. Statement imports feed GOAT Statements & Smart totals; they do not replace this engine yet.',
                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 10, height: 1.35),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _horizonChip(context, ref, 7, horizon),
                    _horizonChip(context, ref, 30, horizon),
                    _horizonChip(context, ref, 60, horizon),
                    _horizonChip(context, ref, 90, horizon),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reserveCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Reserve buffer (same currency)',
                    hintText: 'Amount to always hold back',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (v) {
                    final x = double.tryParse(v.replaceAll(',', '')) ?? 0;
                    ref.read(forecastReserveProvider.notifier).setReservePaise(CashflowMoneyLine.toMinor(x));
                    ref.invalidate(goatForecastProvider);
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      final x = double.tryParse(_reserveCtrl.text.replaceAll(',', '')) ?? 0;
                      ref.read(forecastReserveProvider.notifier).setReservePaise(CashflowMoneyLine.toMinor(x));
                      ref.invalidate(goatForecastProvider);
                    },
                    child: const Text('Apply buffer'),
                  ),
                ),
                const SizedBox(height: 12),
                forecast.when(
                  loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2))),
                  error: (e, _) => Text(
                    'Forecast unavailable. Add accounts / recurring / income, and apply DB migrations for forecast tables.\n\n$e',
                    style: TextStyle(color: GoatTokens.textMuted, height: 1.4),
                  ),
                  data: (f) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (f.riskLevel == 'high')
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7F1D1D).withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFCA5A5).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            'High risk: projected balance may go negative or safe-to-spend is below zero in this model.',
                            style: TextStyle(color: GoatTokens.textPrimary, fontSize: 12, height: 1.35),
                          ),
                        ),
                      GoatPremiumCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Safe to spend (now)', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(
                              AppCurrency.format(CashflowMoneyLine.fromMinor(f.safeToSpendNowMinor), currency),
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: GoatTokens.gold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '7-day view: ${AppCurrency.format(CashflowMoneyLine.fromMinor(f.safeToSpend7dMinor), currency)}',
                              style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                            ),
                            if (f.nextIncomeDate != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Next income (in model): ${f.nextIncomeDate!.year}-${f.nextIncomeDate!.month.toString().padLeft(2, '0')}-${f.nextIncomeDate!.day.toString().padLeft(2, '0')}',
                                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                                ),
                              ),
                            if (whatIfPaise > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Includes what-if spend today: ${AppCurrency.format(CashflowMoneyLine.fromMinor(whatIfPaise), currency)}',
                                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                                ),
                              ),
                            goalsSummary.when(
                              data: (gs) {
                                if (gs.softReserveMonthlyMinor <= 0) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                    'Goals (soft reserve, informational): ${AppCurrency.format(CashflowMoneyLine.fromMinor(gs.softReserveMonthlyMinor), currency)}/mo in planned pace — not subtracted from safe-to-spend.',
                                    style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.35),
                                  ),
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (e, st) => const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _openWhatIfDialog(context, ref, currency),
                              child: const Text('What if I spend…'),
                            ),
                          ),
                          if (whatIfPaise > 0) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                ref.read(whatIfSpendTodayProvider.notifier).clear();
                                ref.invalidate(goatForecastProvider);
                              },
                              child: const Text('Clear'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      GoatPremiumCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Projection', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(
                              'Lowest balance in horizon: ${AppCurrency.format(CashflowMoneyLine.fromMinor(f.projectedMinBalanceMinor), currency)}',
                              style: TextStyle(color: GoatTokens.textPrimary, fontSize: 13),
                            ),
                            if (f.lowestBalanceDate != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Trough date: ${f.lowestBalanceDate!.year}-${f.lowestBalanceDate!.month.toString().padLeft(2, '0')}-${f.lowestBalanceDate!.day.toString().padLeft(2, '0')}',
                                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              'End balance (day ${f.horizonDays}): ${AppCurrency.format(CashflowMoneyLine.fromMinor(f.projectedEndBalanceMinor), currency)}',
                              style: TextStyle(color: GoatTokens.textMuted, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text('Risk: ${f.riskLevel}', style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w700, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text('Why this number?', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700)),
                        children: [
                          ...f.breakdownLines.map(
                            (l) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(child: Text(l.label, style: TextStyle(color: GoatTokens.textMuted, fontSize: 12))),
                                  Text(
                                    _formatBreakdownAmount(l, currency),
                                    style: TextStyle(color: GoatTokens.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Formula uses liquid included balances − reserve − committed outflows until next income (or horizon end) + inflows in that window. Integer paise math in engine.',
                            style: TextStyle(color: GoatTokens.textMuted, fontSize: 10, height: 1.35),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Next 14 days', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      ...f.days.take(14).map(
                            (d) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: GoatPremiumCard(
                                accentBorder: false,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}',
                                        style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                                      ),
                                    ),
                                    Text(
                                      '${AppCurrency.format(CashflowMoneyLine.fromMinor(d.inflowMinor), currency)} in',
                                      style: TextStyle(color: const Color(0xFF86EFAC), fontSize: 11),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${AppCurrency.format(CashflowMoneyLine.fromMinor(d.outflowMinor), currency)} out',
                                      style: TextStyle(color: const Color(0xFFFCA5A5), fontSize: 11),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      AppCurrency.format(CashflowMoneyLine.fromMinor(d.closingMinor), currency),
                                      style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w700, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Setup', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openAccountSheet(context, ref),
                      icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                      label: const Text('Add account'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openIncomeSheet(context, ref),
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Add income'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openPlannedSheet(context, ref),
                      icon: const Icon(Icons.event_note_outlined, size: 18),
                      label: const Text('Planned event'),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatBreakdownAmount(CashflowMoneyLine l, String currency) {
    final raw = CashflowMoneyLine.fromMinor(l.minor);
    final fmt = AppCurrency.format(raw.abs(), currency);
    switch (l.kind) {
      case 'breakdown_sub':
        return raw == 0 ? fmt : '−$fmt';
      case 'breakdown_add':
        return raw == 0 ? fmt : '+$fmt';
      case 'breakdown_note':
        return '—';
      default:
        return AppCurrency.format(raw, currency);
    }
  }

  Future<void> _openWhatIfDialog(BuildContext context, WidgetRef ref, String currency) async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GoatTokens.surface,
        title: Text('What if I spend today?', style: TextStyle(color: GoatTokens.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Extra outflow today ($currency)',
            border: const OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final x = double.tryParse(ctrl.text.replaceAll(',', '')) ?? 0;
              ref.read(whatIfSpendTodayProvider.notifier).setPaise(CashflowMoneyLine.toMinor(x));
              ref.invalidate(goatForecastProvider);
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Widget _horizonChip(BuildContext context, WidgetRef ref, int days, int selected) {
    final sel = selected == days;
    return FilterChip(
      label: Text('${days}d'),
      selected: sel,
      onSelected: (_) {
        ref.read(goatForecastHorizonProvider.notifier).setDays(days);
        ref.invalidate(goatForecastProvider);
      },
      selectedColor: GoatTokens.gold.withValues(alpha: 0.25),
      checkmarkColor: GoatTokens.gold,
      labelStyle: TextStyle(color: sel ? GoatTokens.textPrimary : GoatTokens.textMuted, fontWeight: FontWeight.w600, fontSize: 12),
    );
  }

  Future<void> _openAccountSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GoatTokens.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AddAccountSheet(
        onSaved: () {
          ref.invalidate(financialAccountsProvider);
          ref.invalidate(goatForecastProvider);
        },
      ),
    );
  }

  Future<void> _openIncomeSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GoatTokens.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AddIncomeSheet(
        onSaved: () {
          ref.invalidate(incomeStreamsProvider);
          ref.invalidate(goatForecastProvider);
        },
      ),
    );
  }

  Future<void> _openPlannedSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GoatTokens.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AddPlannedSheet(
        onSaved: () {
          ref.invalidate(plannedCashEventsProvider);
          ref.invalidate(goatForecastProvider);
        },
      ),
    );
  }
}

class _AddAccountSheet extends StatefulWidget {
  const _AddAccountSheet({required this.onSaved});
  final VoidCallback onSaved;

  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  final _name = TextEditingController();
  final _balance = TextEditingController();
  String _type = 'bank';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 16 + pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Add account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
            controller: _balance,
            decoration: const InputDecoration(labelText: 'Current balance', border: OutlineInputBorder()),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'bank', child: Text('Bank')),
              DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
              DropdownMenuItem(value: 'credit_card', child: Text('Credit card')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'bank'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    final bal = double.tryParse(_balance.text.replaceAll(',', '')) ?? 0;
                    if (_name.text.trim().isEmpty) return;
                    setState(() => _saving = true);
                    try {
                      await FinanceRepository.upsertAccount(
                        name: _name.text.trim(),
                        accountType: _type,
                        currentBalance: bal,
                      );
                      widget.onSaved();
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _AddIncomeSheet extends StatefulWidget {
  const _AddIncomeSheet({required this.onSaved});
  final VoidCallback onSaved;

  @override
  State<_AddIncomeSheet> createState() => _AddIncomeSheetState();
}

class _AddIncomeSheetState extends State<_AddIncomeSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  String _freq = 'monthly';
  DateTime _next = DateTime.now().add(const Duration(days: 28));
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 16 + pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Add income stream', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title (e.g. Salary)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Expected amount', border: OutlineInputBorder()),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _freq,
            decoration: const InputDecoration(labelText: 'Frequency', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              DropdownMenuItem(value: 'biweekly', child: Text('Biweekly')),
              DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              DropdownMenuItem(value: 'irregular', child: Text('Irregular (one next date)')),
            ],
            onChanged: (v) => setState(() => _freq = v ?? 'monthly'),
          ),
          ListTile(
            title: const Text('Next expected date'),
            subtitle: Text('${_next.year}-${_next.month.toString().padLeft(2, '0')}-${_next.day.toString().padLeft(2, '0')}'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _next,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              );
              if (d != null) setState(() => _next = d);
            },
          ),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    final amt = double.tryParse(_amount.text.replaceAll(',', '')) ?? 0;
                    if (_title.text.trim().isEmpty || amt <= 0) return;
                    setState(() => _saving = true);
                    try {
                      await FinanceRepository.insertIncomeStream(
                        title: _title.text.trim(),
                        frequency: _freq,
                        expectedAmount: amt,
                        nextExpectedDate: _next,
                      );
                      widget.onSaved();
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _AddPlannedSheet extends StatefulWidget {
  const _AddPlannedSheet({required this.onSaved});
  final VoidCallback onSaved;

  @override
  State<_AddPlannedSheet> createState() => _AddPlannedSheetState();
}

class _AddPlannedSheetState extends State<_AddPlannedSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  String _dir = 'outflow';
  DateTime _when = DateTime.now().add(const Duration(days: 14));
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 16 + pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Planned cash event', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder()),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          DropdownButtonFormField<String>(
            value: _dir,
            decoration: const InputDecoration(labelText: 'Direction', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'outflow', child: Text('Outflow')),
              DropdownMenuItem(value: 'inflow', child: Text('Inflow')),
            ],
            onChanged: (v) => setState(() => _dir = v ?? 'outflow'),
          ),
          ListTile(
            title: const Text('Date'),
            subtitle: Text('${_when.year}-${_when.month.toString().padLeft(2, '0')}-${_when.day.toString().padLeft(2, '0')}'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _when,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
              );
              if (d != null) setState(() => _when = d);
            },
          ),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    final amt = double.tryParse(_amount.text.replaceAll(',', '')) ?? 0;
                    if (_title.text.trim().isEmpty || amt <= 0) return;
                    setState(() => _saving = true);
                    try {
                      await FinanceRepository.insertPlannedEvent(
                        title: _title.text.trim(),
                        eventDate: _when,
                        amount: amt,
                        direction: _dir,
                      );
                      widget.onSaved();
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
