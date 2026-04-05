import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/usage_limits_provider.dart';
import '../../../services/supabase_service.dart';
import '../../analytics/screens/document_ai_review_screen.dart';
import '../../invoices/services/invoice_ocr_pipeline.dart';
import '../models/document_list_models.dart';
import '../utils/document_json.dart';
import 'document_edit_screen.dart';

/// Full read-only view of a saved document; supports edit, delete, open original scan.
class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _doc;
  Map<String, dynamic>? _invoiceHeader;
  String? _signedUrl;
  bool _busyOcr = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await SupabaseService.fetchDocumentById(widget.documentId);
      if (doc == null || !mounted) {
        setState(() {
          _doc = null;
          _error = 'Document not found';
          _loading = false;
        });
        return;
      }
      final ed = asJsonMap(doc['extracted_data']);
      final invoiceId = ed?['invoice_id']?.toString();
      Map<String, dynamic>? inv;
      String? url;
      if (invoiceId != null && invoiceId.isNotEmpty) {
        inv = await SupabaseService.fetchInvoiceHeaderForUser(invoiceId);
        final path = inv?['file_path'] as String?;
        if (path != null && path.isNotEmpty) {
          url = await SupabaseService.signedUrlForInvoiceFile(path);
        }
      }
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _invoiceHeader = inv;
        _signedUrl = url;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: const Text('This removes the saved entry from your history. Linked scan files may remain in storage until cleaned up separately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BillyTheme.red500),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(documentsProvider.notifier).deleteDoc(widget.documentId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _openOriginal() async {
    final url = _signedUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open file')),
      );
    }
  }

  String _mimeForFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  Future<void> _rerunOcr() async {
    final header = _invoiceHeader;
    final path = header?['file_path'] as String?;
    final id = header?['id']?.toString();
    if (id == null || id.isEmpty || path == null || path.isEmpty) return;

    setState(() => _busyOcr = true);
    try {
      await SupabaseService.incrementRefreshCount();
      ref.invalidate(usageLimitsProvider);

      await InvoiceOcrPipeline.reprocessExistingInvoice(invoiceId: id, filePath: path);
      await ref.read(documentsProvider.notifier).syncDocumentFromLinkedInvoice(widget.documentId);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busyOcr = false);
    }
  }

  Future<void> _replaceScan() async {
    final header = _invoiceHeader;
    final path = header?['file_path'] as String?;
    final id = header?['id']?.toString();
    if (id == null || id.isEmpty || path == null || path.isEmpty) return;

    final pick = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
    );
    if (pick == null || pick.files.isEmpty) return;
    final f = pick.files.single;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read that file. Try another image or PDF.')),
        );
      }
      return;
    }

    setState(() => _busyOcr = true);
    try {
      await SupabaseService.incrementRefreshCount();
      ref.invalidate(usageLimitsProvider);

      await InvoiceOcrPipeline.replaceInvoiceFileAndReprocess(
        invoiceId: id,
        filePath: path,
        bytes: bytes,
        mimeType: _mimeForFileName(f.name),
      );
      await ref.read(documentsProvider.notifier).syncDocumentFromLinkedInvoice(widget.documentId);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busyOcr = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String? ??
        (_doc?['currency'] as String?) ??
        'INR';

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('Document'),
        backgroundColor: BillyTheme.scaffoldBg,
        foregroundColor: BillyTheme.gray800,
        elevation: 0,
        actions: [
          if (_doc != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => DocumentEditScreen(documentId: widget.documentId),
                  ),
                );
                if (changed == true && mounted) await _load();
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: BillyTheme.emerald600))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _doc == null
                  ? const Center(child: Text('Not found'))
                  : _buildBody(currency),
    );
  }

  Widget _buildBody(String currencyCode) {
    final doc = _doc!;
    final ed = asJsonMap(doc['extracted_data']);
    final vendor = doc['vendor_name'] as String? ?? 'Unknown';
    final amount = (doc['amount'] as num?)?.toDouble() ?? 0;
    final taxAmount = (doc['tax_amount'] as num?)?.toDouble() ?? 0;
    final dateStr = doc['date'] as String? ?? '';
    final type = doc['type'] as String? ?? 'receipt';
    final desc = doc['description'] as String? ?? '';
    final payment = doc['payment_method'] as String?;
    final ocr = documentIsOcr(doc);

    String dateLabel = dateStr;
    try {
      dateLabel = DateFormat('EEEE, dd MMM yyyy').format(DateTime.parse(dateStr));
    } catch (_) {}

    final invNum = stringFromEd(ed, 'invoice_number');
    final notes = stringFromEd(ed, 'notes');
    final categoryFromEd = stringFromEd(ed, 'category');
    final category = categoryFromEd ?? (desc.isNotEmpty ? desc.split(',').first.trim() : null);

    final cgst = doubleFromEd(ed, 'cgst');
    final sgst = doubleFromEd(ed, 'sgst');
    final igst = doubleFromEd(ed, 'igst');
    final discount = doubleFromEd(ed, 'discount');
    final subtotal = doubleFromEd(ed, 'subtotal');
    final conf = stringFromEd(ed, 'extraction_confidence') ?? '—';

    final lineItems = ed == null
        ? <Map<String, dynamic>>[]
        : (ed['line_items'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];

    final lineSel = ed == null
        ? <Map<String, dynamic>>[]
        : (ed['line_selection'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];

    final intentGroup = ed?['intent_group_expense'] == true;
    final groupId = ed?['group_id']?.toString();
    final intentLend = ed?['intent_lend_borrow'] == true;
    final lendType = ed?['lend_type']?.toString();
    final lendParty = ed?['lend_counterparty']?.toString();

    final repairPath = _invoiceHeader?['file_path'] as String?;
    final repairId = _invoiceHeader?['id']?.toString();
    final canOcrRepair = ocr &&
        repairPath != null &&
        repairPath.isNotEmpty &&
        repairId != null &&
        repairId.isNotEmpty;

    final usageAsync = ref.watch(usageLimitsProvider);
    final refreshLocked = usageAsync.maybeWhen(
      data: (m) {
        if (m == null) return false;
        final used = (m['refresh_used'] as num?)?.toInt() ?? 0;
        final limit = (m['refresh_limit'] as num?)?.toInt() ?? 5;
        return used >= limit;
      },
      orElse: () => false,
    );

    return RefreshIndicator(
      color: BillyTheme.emerald600,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            children: [
              _chip(type == 'invoice' ? 'Invoice' : 'Receipt', BillyTheme.gray100, BillyTheme.gray700),
              if (ocr) ...[
                const SizedBox(width: 8),
                _chip('OCR', BillyTheme.emerald50, BillyTheme.emerald700),
              ],
              if (ocr) ...[
                const SizedBox(width: 8),
                _chip('Review: $conf', BillyTheme.gray50, BillyTheme.gray600),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            vendor,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: BillyTheme.gray800),
          ),
          const SizedBox(height: 8),
          Text(
            AppCurrency.format(amount, currencyCode),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: BillyTheme.emerald700),
          ),
          const SizedBox(height: 4),
          Text(dateLabel, style: const TextStyle(color: BillyTheme.gray500, fontSize: 14)),
          if (invNum != null) ...[
            const SizedBox(height: 12),
            _rowLabel('Invoice #', invNum),
          ],
          if (category != null && category.isNotEmpty) _rowLabel('Category', category),
          if (payment != null && payment.isNotEmpty) _rowLabel('Payment', payment),
          if (notes != null && notes.isNotEmpty) _rowLabel('Notes', notes),

          if (subtotal > 0 || cgst > 0 || sgst > 0 || igst > 0 || discount > 0 || taxAmount > 0) ...[
            const SizedBox(height: 20),
            const Text('Amounts & tax', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            if (subtotal > 0) _rowLabel('Subtotal', AppCurrency.format(subtotal, currencyCode)),
            if (cgst > 0) _rowLabel('CGST', AppCurrency.format(cgst, currencyCode)),
            if (sgst > 0) _rowLabel('SGST', AppCurrency.format(sgst, currencyCode)),
            if (igst > 0) _rowLabel('IGST', AppCurrency.format(igst, currencyCode)),
            if (discount > 0) _rowLabel('Discount', AppCurrency.format(discount, currencyCode)),
            if (taxAmount > 0 && cgst + sgst + igst == 0) _rowLabel('Tax (total)', AppCurrency.format(taxAmount, currencyCode)),
          ],

          if (lineItems.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Line items (${lineItems.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            ...lineItems.asMap().entries.map((e) {
              final i = e.key;
              final li = e.value;
              final desc = li['description']?.toString() ?? '';
              final amt = (li['amount'] as num?)?.toDouble() ?? (li['total'] as num?)?.toDouble() ?? 0.0;
              final qty = li['quantity'];
              String suffix = '';
              if (lineSel.isNotEmpty && i < lineSel.length) {
                final inc = lineSel[i]['included'];
                suffix = inc == false ? ' (excluded)' : ' (included)';
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: BillyTheme.gray50),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(desc, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (qty != null) Text('Qty: $qty', style: const TextStyle(fontSize: 12, color: BillyTheme.gray500)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(AppCurrency.format(amt, currencyCode), style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (suffix.isNotEmpty)
                            Text(suffix, style: const TextStyle(fontSize: 11, color: BillyTheme.gray400)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],

          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DocumentAiReviewScreen(documentId: widget.documentId),
                ),
              );
            },
            icon: const Icon(Icons.psychology_outlined),
            label: const Text('Analyze this document'),
          ),

          if (intentGroup || intentLend) ...[
            const SizedBox(height: 20),
            const Text('Linked actions at save', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            if (intentGroup)
              Text(
                'Group expense was created${groupId != null ? ' (group id: $groupId)' : ''}. Open the Friends tab to review splits.',
                style: const TextStyle(color: BillyTheme.gray600, height: 1.4),
              ),
            if (intentLend)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Lend / borrow entry was recorded${lendType != null ? ' ($lendType)' : ''}${lendParty != null ? ' — $lendParty' : ''}.',
                  style: const TextStyle(color: BillyTheme.gray600, height: 1.4),
                ),
              ),
          ],

          if (_invoiceHeader != null) ...[
            const SizedBox(height: 16),
            Text(
              'Scan status: ${_invoiceHeader!['status'] ?? '—'}',
              style: const TextStyle(fontSize: 13, color: BillyTheme.gray500),
            ),
          ],

          if (_signedUrl != null) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _busyOcr ? null : _openOriginal,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open original file'),
            ),
          ],

          if (canOcrRepair) ...[
            const SizedBox(height: 20),
            const Text(
              'Trust & recovery',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Re-run OCR on the stored file, or upload a clearer scan to replace it. Line selections and split intents are preserved when possible.',
              style: TextStyle(fontSize: 13, color: BillyTheme.gray500, height: 1.35),
            ),
            if (refreshLocked) ...[
              const SizedBox(height: 8),
              Text(
                'You have reached your monthly limit for re-runs and replacements. Limits reset each billing period.',
                style: TextStyle(fontSize: 12, color: BillyTheme.red500, height: 1.35),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: (refreshLocked || _busyOcr) ? null : _rerunOcr,
              icon: _busyOcr
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: BillyTheme.emerald600),
                    )
                  : const Icon(Icons.auto_fix_high_outlined),
              label: Text(_busyOcr ? 'Working…' : 'Re-run OCR'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: (refreshLocked || _busyOcr) ? null : _replaceScan,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Replace scan file'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _rowLabel(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: const TextStyle(color: BillyTheme.gray500, fontSize: 14)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14))),
        ],
      ),
    );
  }
}
