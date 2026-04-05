import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../core/utils/analytics_fingerprint.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/usage_limits_provider.dart';
import '../../documents/screens/documents_history_screen.dart';
import '../models/analytics_insights_models.dart';
import '../providers/analytics_insights_provider.dart';

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

/// AI Insights segment: rule-based snapshot from cache + manual refresh (one Edge + optional Gemini per tap).
class AiInsightsPanel extends ConsumerStatefulWidget {
  const AiInsightsPanel({super.key, required this.rangePreset});

  /// `1W` | `1M` | `3M` — must match analytics date filter.
  final String rangePreset;

  @override
  ConsumerState<AiInsightsPanel> createState() => _AiInsightsPanelState();
}

class _AiInsightsPanelState extends ConsumerState<AiInsightsPanel> {
  bool _refreshBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsInsightsProvider.notifier).loadCachedSnapshot(widget.rangePreset);
    });
  }

  @override
  void didUpdateWidget(covariant AiInsightsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rangePreset != widget.rangePreset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(analyticsInsightsProvider.notifier).loadCachedSnapshot(widget.rangePreset);
      });
    }
  }

  Future<void> _onRefreshInsights() async {
    if (_refreshBusy) return;
    setState(() => _refreshBusy = true);
    final err = await ref.read(analyticsInsightsProvider.notifier).refreshInsights(widget.rangePreset);
    if (mounted) {
      setState(() => _refreshBusy = false);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
      }
    }
  }

  void _openDocuments(Set<String> ids) {
    if (ids.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentsHistoryScreen(restrictToDocumentIds: ids),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(analyticsInsightsProvider);
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String?;
    final refreshLocked = ref.watch(usageLimitsProvider).maybeWhen(
      data: (m) {
        if (m == null) return false;
        final used = (m['refresh_used'] as num?)?.toInt() ?? 0;
        final limit = (m['refresh_limit'] as num?)?.toInt() ?? 5;
        return used >= limit;
      },
      orElse: () => false,
    );
    final result = async.valueOrNull;
    final docs = ref.watch(documentsProvider).valueOrNull ?? [];
    final liveFp = analyticsDataFingerprintForPreset(docs, widget.rangePreset);
    final snapFp = result?.dataFingerprint;
    final insightsStale = result != null &&
        snapFp != null &&
        snapFp.isNotEmpty &&
        liveFp != snapFp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BillyTheme.emerald50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BillyTheme.emerald100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manual refresh only',
                style: TextStyle(fontWeight: FontWeight.w700, color: BillyTheme.emerald700, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                'Insights are not regenerated automatically. Tap Refresh when you want updated numbers and a short AI summary (counts toward your monthly refresh limit).',
                style: TextStyle(fontSize: 12, color: BillyTheme.gray600, height: 1.35),
              ),
            ],
          ),
        ),
        if (insightsStale) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BillyTheme.yellow400.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: BillyTheme.yellow400.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.update_outlined, size: 22, color: BillyTheme.gray800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your documents changed since this insight was generated. Tap Refresh insights for numbers and AI text that match your vault.',
                    style: TextStyle(fontSize: 12, color: BillyTheme.gray700, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                _lastUpdatedLabel(result),
                style: const TextStyle(fontSize: 12, color: BillyTheme.gray500),
              ),
            ),
            FilledButton.icon(
              onPressed: (_refreshBusy || refreshLocked) ? null : _onRefreshInsights,
              icon: _refreshBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh_rounded, size: 20),
              label: Text(_refreshBusy ? 'Refreshing…' : 'Refresh insights'),
              style: FilledButton.styleFrom(
                backgroundColor: BillyTheme.emerald600,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        if (refreshLocked) ...[
          const SizedBox(height: 8),
          Text(
            'Monthly refresh limit reached.',
            style: TextStyle(fontSize: 12, color: BillyTheme.red500, height: 1.35),
          ),
        ],
        if (async.isLoading && result == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator(color: BillyTheme.emerald600)),
          )
        else if (result == null && !async.isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No saved insights yet for this range. Tap Refresh insights to generate.',
              style: TextStyle(color: BillyTheme.gray500, height: 1.4),
            ),
          )
        else if (result != null) ...[
          const SizedBox(height: 16),
          ..._buildCards(context, result, currency),
        ],
      ],
    );
  }

  String _lastUpdatedLabel(AnalyticsInsightsResult? r) {
    if (r?.generatedAt == null) return 'Not generated yet';
    final fmt = DateFormat('MMM d, y • HH:mm');
    return 'Last updated ${fmt.format(r!.generatedAt!.toLocal())}';
  }

  List<Widget> _buildCards(
    BuildContext context,
    AnalyticsInsightsResult result,
    String? currency,
  ) {
    final det = result.deterministic;
    if (det == null) return [];

    final summary = det['summary'];
    final tax = det['tax_summary'];
    final attention = det['needs_attention'];
    final merchants = (det['top_merchants'] as List<dynamic>?) ?? [];
    final dups = (attention is Map ? attention['duplicate_groups'] : null) as List<dynamic>? ?? [];

    final widgets = <Widget>[];

    if (summary is Map) {
      final total = _asDouble(summary['total_spend']);
      final count = (summary['document_count'] as num?)?.toInt() ?? 0;
      final prev = _asDouble(summary['previous_period_total']);
      final ch = summary['change_vs_previous_pct'];
      final chInt = ch is num ? ch.round() : null;
      widgets.add(
        _InsightCard(
          title: 'Period summary',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppCurrency.format(total, currency),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: BillyTheme.gray800),
              ),
              const SizedBox(height: 4),
              Text('$count documents', style: const TextStyle(color: BillyTheme.gray500, fontSize: 13)),
              if (chInt != null && prev > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${chInt >= 0 ? '+' : ''}$chInt% vs previous period',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: chInt > 0 ? BillyTheme.red400 : BillyTheme.emerald700,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (tax is Map) {
      final tt = _asDouble(tax['total_tax']);
      final dwc = (tax['documents_with_tax'] as num?)?.toInt() ?? 0;
      widgets.add(
        _InsightCard(
          title: 'Tax snapshot',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppCurrency.format(tt, currency),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '$dwc documents with tax lines',
                style: const TextStyle(fontSize: 13, color: BillyTheme.gray500),
              ),
            ],
          ),
        ),
      );
    }

    if (attention is Map) {
      final unc = (attention['uncategorized_count'] as num?)?.toInt() ?? 0;
      final uncIds = _idSet(attention['uncategorized_document_ids']);
      final rev = (attention['review_recommended_count'] as num?)?.toInt() ?? 0;
      final revIds = _idSet(attention['review_recommended_document_ids']);
      final low = (attention['low_confidence_ocr_count'] as num?)?.toInt() ?? 0;
      final lowIds = _idSet(attention['low_confidence_document_ids']);

      widgets.add(
        _InsightCard(
          title: 'Needs attention',
          child: Column(
            children: [
              if (unc > 0)
                _AttentionTile(
                  label: '$unc uncategorized — tap to review',
                  onTap: () => _openDocuments(uncIds),
                ),
              if (rev > 0)
                _AttentionTile(
                  label: '$rev OCR review recommended',
                  onTap: () => _openDocuments(revIds),
                ),
              if (low > 0)
                _AttentionTile(
                  label: '$low low-confidence OCR',
                  onTap: () => _openDocuments(lowIds),
                ),
              if (unc == 0 && rev == 0 && low == 0)
                const Text('Nothing flagged in this range.', style: TextStyle(color: BillyTheme.gray500)),
            ],
          ),
        ),
      );
    }

    if (merchants.isNotEmpty) {
      final top = merchants.take(4).toList();
      widgets.add(
        _InsightCard(
          title: 'Top merchants',
          child: Column(
            children: top.map((m) {
              if (m is! Map) return const SizedBox.shrink();
              final name = m['name']?.toString() ?? '—';
              final amt = _asDouble(m['amount']);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w500))),
                    Text(AppCurrency.format(amt, currency), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      );
    }

    if (dups.isNotEmpty) {
      widgets.add(
        _InsightCard(
          title: 'Possible duplicates',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Same date, amount, and merchant — open to compare.',
                style: TextStyle(fontSize: 12, color: BillyTheme.gray500),
              ),
              const SizedBox(height: 8),
              ...dups.whereType<Map>().map((g) {
                final ids = _idSet(g['document_ids']);
                final reason = g['reason']?.toString() ?? '';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${ids.length} receipts', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(reason, style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openDocuments(ids),
                );
              }),
            ],
          ),
        ),
      );
    }

    final narrative = result.shortNarrative?.trim();
    final insights = result.prioritizedInsights;
    widgets.add(
      _InsightCard(
        title: 'Analyst notes (AI)',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (narrative != null && narrative.isNotEmpty)
              Text(narrative, style: const TextStyle(fontSize: 14, height: 1.4, color: BillyTheme.gray800))
            else
              Text(
                result.geminiUsed == false
                    ? 'No AI narrative yet. Add a Gemini API key on your profile (or set GEMINI_API_KEY on the function), then tap Refresh insights.'
                    : 'Tap Refresh insights to generate a short narrative from your data.',
                style: TextStyle(fontSize: 13, color: BillyTheme.gray500, height: 1.35),
              ),
            ...insights.map((Map<String, dynamic> it) {
              final text = it['text']?.toString() ?? '';
              final ids = _idSet(it['document_ids']);
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: InkWell(
                  onTap: ids.isEmpty ? null : () => _openDocuments(ids),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.arrow_circle_right_outlined,
                        size: 18,
                        color: ids.isEmpty ? BillyTheme.gray300 : BillyTheme.emerald600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );

    return widgets;
  }

  static Set<String> _idSet(dynamic raw) {
    if (raw is! List) return {};
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toSet();
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BillyTheme.gray50),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}
