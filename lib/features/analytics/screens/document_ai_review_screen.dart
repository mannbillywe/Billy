import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/profile_provider.dart';
import '../../../services/supabase_service.dart';
import '../../documents/models/document_list_models.dart';
import '../../documents/utils/document_json.dart';
import '../services/analytics_insights_service.dart';

/// On-demand AI review for one document. No Edge/Gemini calls until the user taps **Run AI review**.
class DocumentAiReviewScreen extends ConsumerStatefulWidget {
  const DocumentAiReviewScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<DocumentAiReviewScreen> createState() => _DocumentAiReviewScreenState();
}

class _DocumentAiReviewScreenState extends ConsumerState<DocumentAiReviewScreen> {
  Map<String, dynamic>? _doc;
  bool _loadingDoc = true;
  String? _loadError;
  Map<String, dynamic>? _aiLayer;
  bool _loadingAi = false;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    _loadLocalDoc();
  }

  Future<void> _loadLocalDoc() async {
    setState(() {
      _loadingDoc = true;
      _loadError = null;
    });
    try {
      final doc = await SupabaseService.fetchDocumentById(widget.documentId);
      if (!mounted) return;
      if (doc == null) {
        setState(() {
          _loadError = 'Document not found';
          _loadingDoc = false;
        });
        return;
      }
      setState(() {
        _doc = doc;
        _loadingDoc = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loadingDoc = false;
        });
      }
    }
  }

  Future<void> _runAiReview() async {
    setState(() {
      _loadingAi = true;
      _aiError = null;
    });
    try {
      final r = await AnalyticsInsightsService.reviewDocument(
        documentId: widget.documentId,
        includeAi: true,
      );
      if (!mounted) return;
      setState(() {
        _aiLayer = r.aiLayer;
        _loadingAi = false;
      });
      if (r.geminiUsed != true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI review skipped — check your Gemini API key.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiError = e.toString();
          _loadingAi = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String?;

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('Document review'),
        backgroundColor: BillyTheme.scaffoldBg,
        foregroundColor: BillyTheme.gray800,
        elevation: 0,
      ),
      body: _loadingDoc
          ? const Center(child: CircularProgressIndicator(color: BillyTheme.emerald600))
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _loadLocalDoc, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    const Text(
                      'Facts from your saved document',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Gemini runs only when you tap Run AI review.',
                      style: TextStyle(fontSize: 13, color: BillyTheme.gray500, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    ..._factTiles(_doc!, currency),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _loadingAi ? null : _runAiReview,
                      icon: _loadingAi
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.psychology_outlined),
                      label: Text(_loadingAi ? 'Working…' : 'Run AI review'),
                      style: FilledButton.styleFrom(
                        backgroundColor: BillyTheme.emerald600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    if (_aiError != null) ...[
                      const SizedBox(height: 12),
                      Text(_aiError!, style: const TextStyle(color: BillyTheme.red500, fontSize: 13)),
                    ],
                    if (_aiLayer != null) ...[
                      const SizedBox(height: 28),
                      const Text(
                        'AI review',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      _aiLayerBody(_aiLayer!),
                    ],
                  ],
                ),
    );
  }

  List<Widget> _factTiles(Map<String, dynamic> doc, String? currency) {
    final ed = asJsonMap(doc['extracted_data']);
    final vendor = doc['vendor_name'] as String? ?? '—';
    final amount = (doc['amount'] as num?)?.toDouble() ?? 0;
    final date = doc['date'] as String? ?? '—';
    final tax = (doc['tax_amount'] as num?)?.toDouble() ?? 0;
    final desc = doc['description'] as String? ?? '';
    final catFromDesc = desc.isNotEmpty ? desc.split(',').first.trim() : null;
    final catEd = stringFromEd(ed, 'category');
    final category = catEd ?? catFromDesc ?? '—';
    final ocr = documentIsOcr(doc);
    final conf = stringFromEd(ed, 'extraction_confidence') ?? '—';
    final review = ocr && (conf == 'low' || ed?['user_flagged_mismatch'] == true);

    return [
      _tile('Vendor', vendor),
      _tile('Amount', AppCurrency.format(amount, currency)),
      _tile('Date', date),
      _tile('Category', category),
      if (tax > 0) _tile('Tax', AppCurrency.format(tax, currency)),
      _tile('Source', ocr ? 'OCR' : 'Manual'),
      if (ocr) _tile('OCR confidence', conf),
      if (review) _tile('Review', 'Recommended'),
    ];
  }

  Widget _tile(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: const TextStyle(color: BillyTheme.gray500, fontSize: 13)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        ],
      ),
    );
  }

  Widget _aiLayerBody(Map<String, dynamic> ai) {
    final summary = ai['review_summary']?.toString();
    final checks = ai['checks'];
    final actions = ai['suggested_actions'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null && summary.isNotEmpty)
          Text(summary, style: const TextStyle(fontSize: 14, height: 1.45)),
        if (checks is List) ...[
          const SizedBox(height: 12),
          ...checks.whereType<Map>().map((c) {
            final label = c['label']?.toString() ?? '';
            final ok = c['ok'] == true;
            final detail = c['detail']?.toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    ok ? Icons.check_circle_outline : Icons.flag_outlined,
                    size: 18,
                    color: ok ? BillyTheme.emerald600 : BillyTheme.red400,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        if (detail != null && detail.isNotEmpty)
                          Text(detail, style: const TextStyle(fontSize: 12, color: BillyTheme.gray500, height: 1.3)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        if (actions is List && actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Suggested actions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ...actions.map(
            (a) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• ${a.toString()}', style: const TextStyle(fontSize: 13, height: 1.35)),
            ),
          ),
        ],
      ],
    );
  }
}
