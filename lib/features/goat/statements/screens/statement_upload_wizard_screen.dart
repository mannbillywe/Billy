import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/goat_theme.dart';
import '../../../../providers/documents_provider.dart';
import '../../../../providers/goat_cash_providers.dart' show goatForecastProvider;
import '../../../../providers/goat_statements_providers.dart';
import '../../../../providers/profile_provider.dart';
import '../../widgets/goat_premium_card.dart';
import '../statement_pdf_text_service.dart';
import '../statement_repository.dart';
import '../statement_tabular_engine.dart';

/// Multi-step statement import: file (browse / web drop) → preview → optional column map → mode → commit.
class StatementUploadWizardScreen extends ConsumerStatefulWidget {
  const StatementUploadWizardScreen({super.key});

  @override
  ConsumerState<StatementUploadWizardScreen> createState() => _StatementUploadWizardScreenState();
}

class _StatementUploadWizardScreenState extends ConsumerState<StatementUploadWizardScreen> {
  static const _totalSteps = 6;

  int _step = 0;
  Uint8List? _bytes;
  String _fileName = '';
  String _mime = 'application/octet-stream';
  StatementFormatDetection? _detection;
  StatementParseOutcome? _parse;
  ColumnMapping? _mappingOverride;
  String _accountType = 'bank';
  /// DB [statement_imports.source_hint]; null = auto-detect.
  String? _sourceHintDb;
  String _importMode = 'smart';
  bool _busy = false;
  StatementCommitResult? _result;
  String? _error;
  bool _savedReviewOnly = false;
  DropzoneViewController? _dz;

  late final TextEditingController _cDate;
  late final TextEditingController _cDesc;
  late final TextEditingController _cDebit;
  late final TextEditingController _cCredit;
  late final TextEditingController _cAmount;
  late final TextEditingController _cBalance;
  late final TextEditingController _cRef;

  @override
  void initState() {
    super.initState();
    _cDate = TextEditingController();
    _cDesc = TextEditingController();
    _cDebit = TextEditingController();
    _cCredit = TextEditingController();
    _cAmount = TextEditingController();
    _cBalance = TextEditingController();
    _cRef = TextEditingController();
  }

  @override
  void dispose() {
    _cDate.dispose();
    _cDesc.dispose();
    _cDebit.dispose();
    _cCredit.dispose();
    _cAmount.dispose();
    _cBalance.dispose();
    _cRef.dispose();
    super.dispose();
  }

  int? _intOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  ColumnMapping _mappingFromFields() {
    return ColumnMapping(
      dateCol: _intOrNull(_cDate.text),
      descriptionCol: _intOrNull(_cDesc.text),
      debitCol: _intOrNull(_cDebit.text),
      creditCol: _intOrNull(_cCredit.text),
      amountCol: _intOrNull(_cAmount.text),
      balanceCol: _intOrNull(_cBalance.text),
      referenceCol: _intOrNull(_cRef.text),
    );
  }

  void _prefillMappingFields(ColumnMapping? m) {
    final x = m ?? const ColumnMapping();
    _cDate.text = x.dateCol != null ? '${x.dateCol}' : '';
    _cDesc.text = x.descriptionCol != null ? '${x.descriptionCol}' : '';
    _cDebit.text = x.debitCol != null ? '${x.debitCol}' : '';
    _cCredit.text = x.creditCol != null ? '${x.creditCol}' : '';
    _cAmount.text = x.amountCol != null ? '${x.amountCol}' : '';
    _cBalance.text = x.balanceCol != null ? '${x.balanceCol}' : '';
    _cRef.text = x.referenceCol != null ? '${x.referenceCol}' : '';
  }

  String _mimeForExtension(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'csv':
        return 'text/csv';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _applyPickedBytes(Uint8List b, String name, String mime) async {
    if (b.isEmpty) {
      setState(() => _error = 'Could not read file bytes.');
      return;
    }
    if (b.length > StatementTabularEngine.maxUploadBytes) {
      setState(() => _error = 'File exceeds 15 MB.');
      return;
    }
    setState(() {
      _bytes = b;
      _fileName = name;
      _mime = mime;
      _error = null;
      _detection = null;
      _parse = null;
      _mappingOverride = null;
      _result = null;
      _savedReviewOnly = false;
    });
    await _runDetection();
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'csv', 'xlsx', 'xls', 'png', 'jpg', 'jpeg', 'webp', 'heic', 'heif'],
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final b = f.bytes;
    if (b == null) {
      setState(() => _error = 'Could not read file bytes.');
      return;
    }
    await _applyPickedBytes(b, f.name, _mimeForExtension(f.extension));
  }

  Future<void> _runDetection() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() => _busy = true);
    try {
      final det = StatementTabularEngine.detect(fileName: _fileName, mimeType: _mime, bytes: bytes);
      StatementParseOutcome? outcome;
      switch (det.kind) {
        case StatementFileKind.csv:
        case StatementFileKind.xlsx:
          final grid = StatementTabularEngine.gridFromBytes(det.kind, bytes);
          outcome = StatementTabularEngine.parseGrid(grid, mappingOverride: _mappingOverride);
          break;
        case StatementFileKind.pdfDigital:
        case StatementFileKind.pdfScanned:
          final g = await StatementPdfTextService.extractGrid(bytes);
          if (!g.hasText || g.grid.length < 2) {
            outcome = StatementParseOutcome(
              rows: [],
              confidence: 10,
              mapping: _mappingOverride ?? const ColumnMapping(),
              warnings: const ['No extractable text — export CSV or use a digital statement.'],
            );
          } else {
            outcome = StatementTabularEngine.parseGrid(g.grid, mappingOverride: _mappingOverride);
          }
          break;
        case StatementFileKind.image:
          outcome = StatementParseOutcome(
            rows: [],
            confidence: 0,
            mapping: _mappingOverride ?? const ColumnMapping(),
            warnings: const [
              'Image file — in-app table parsing is not available. Save for review (OCR pipeline) or upload CSV/PDF export.',
            ],
          );
          break;
        case StatementFileKind.xls:
        case StatementFileKind.unsupported:
          outcome = null;
          break;
      }
      setState(() {
        _detection = det;
        _parse = outcome;
        _busy = false;
        _step = 1;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _reparseWithMapping() async {
    final bytes = _bytes;
    final det = _detection;
    if (bytes == null || det == null) return;
    if (det.kind == StatementFileKind.xls ||
        det.kind == StatementFileKind.unsupported ||
        det.kind == StatementFileKind.image) {
      return;
    }

    setState(() => _busy = true);
    try {
      final m = _mappingFromFields();
      _mappingOverride = m;
      switch (det.kind) {
        case StatementFileKind.csv:
        case StatementFileKind.xlsx:
          final grid = StatementTabularEngine.gridFromBytes(det.kind, bytes);
          setState(() {
            _parse = StatementTabularEngine.parseGrid(grid, mappingOverride: _mappingOverride);
            _busy = false;
            _step = 1;
          });
          break;
        case StatementFileKind.pdfDigital:
        case StatementFileKind.pdfScanned:
          final g = await StatementPdfTextService.extractGrid(bytes);
          if (!g.hasText || g.grid.length < 2) {
            setState(() {
              _parse = StatementParseOutcome(
                rows: [],
                confidence: 10,
                mapping: _mappingOverride ?? const ColumnMapping(),
                warnings: const ['No extractable text — export CSV or use a digital statement.'],
              );
              _busy = false;
              _step = 1;
            });
          } else {
            setState(() {
              _parse = StatementTabularEngine.parseGrid(g.grid, mappingOverride: _mappingOverride);
              _busy = false;
              _step = 1;
            });
          }
          break;
        case StatementFileKind.image:
          setState(() => _busy = false);
          break;
        case StatementFileKind.xls:
        case StatementFileKind.unsupported:
          setState(() => _busy = false);
          break;
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _saveNeedsReview() async {
    final bytes = _bytes;
    final det = _detection;
    if (bytes == null || det == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await StatementRepository.registerNeedsReviewImport(
        bytes: bytes,
        fileName: _fileName,
        contentType: _mime,
        detection: det,
        reviewType: 'empty_or_unparsed',
        sourceHint: _sourceHintDb,
        payload: {
          'warnings': _parse?.warnings ?? [],
          'confidence': _parse?.confidence,
        },
      );
      setState(() {
        _busy = false;
        _savedReviewOnly = true;
        _step = 5;
      });
      ref.invalidate(statementImportsProvider);
      ref.invalidate(statementImportReviewsProvider);
      ref.invalidate(statementRowReviewsAllProvider);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _commit() async {
    final bytes = _bytes;
    final parse = _parse;
    final det = _detection;
    if (bytes == null || parse == null || det == null) return;
    if (parse.rows.isEmpty) {
      setState(() => _error = 'Nothing to import.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final importId = await StatementRepository.registerParsedImport(
        bytes: bytes,
        fileName: _fileName,
        contentType: _mime,
        detection: det,
        parse: parse,
        sourceHint: _sourceHintDb,
      );
      final res = await StatementRepository.commitParsedTransactions(
        importId: importId,
        importMode: _importMode,
        rows: parse.rows,
        currency: ref.read(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR',
        accountName: '${_accountType.replaceAll('_', ' ')} · ${_fileName.length > 24 ? _fileName.substring(0, 24) : _fileName}',
        accountType: _accountType,
        parseConfidenceReported: parse.confidence,
      );
      setState(() {
        _result = res;
        _busy = false;
        _savedReviewOnly = false;
        _step = 5;
      });
      ref.invalidate(statementImportsProvider);
      ref.invalidate(statementTransactionsProvider);
      ref.invalidate(statementAccountsProvider);
      ref.invalidate(statementDocumentLinksProvider);
      ref.invalidate(canonicalFinancialEventsProvider);
      ref.invalidate(statementImportReviewsProvider);
      ref.invalidate(statementRowReviewsAllProvider);
      ref.invalidate(goatLensWeekDebitSpendProvider);
      ref.invalidate(goatForecastProvider);
      ref.invalidate(documentsProvider);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  bool get _canParseKind {
    final k = _detection?.kind;
    return k == StatementFileKind.csv ||
        k == StatementFileKind.xlsx ||
        k == StatementFileKind.pdfDigital ||
        k == StatementFileKind.pdfScanned;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Import statement'),
        ),
        body: _busy
            ? const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Step ${_step + 1} of $_totalSteps',
                      style: TextStyle(color: GoatTokens.textMuted, fontSize: 12),
                    ),
                  ),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5), height: 1.35)),
                    const SizedBox(height: 12),
                  ],
                  if (_step == 0) ..._stepChoose(),
                  if (_step == 1) ..._stepPreview(),
                  if (_step == 2) ..._stepMapping(),
                  if (_step == 3) ..._stepMode(),
                  if (_step == 4) ..._stepConfirm(),
                  if (_step == 5) ..._stepDone(),
                ],
              ),
      ),
    );
  }

  List<Widget> _stepChoose() {
    return [
      if (kIsWeb)
        GoatPremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Drop file (web)', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Drag and drop PDF, CSV, XLSX, or payment images (PNG/JPEG/WebP).',
                style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 140,
                  child: DropzoneView(
                    onCreated: (c) => _dz = c,
                    onDropFile: (ev) async {
                      final ctrl = _dz;
                      if (ctrl == null) return;
                      final name = await ctrl.getFilename(ev);
                      final mime = await ctrl.getFileMIME(ev);
                      final data = await ctrl.getFileData(ev);
                      if (data.isEmpty) return;
                      final parts = name.split('.');
                      final ext = parts.length > 1 ? parts.last : null;
                      await _applyPickedBytes(data, name, mime.isNotEmpty ? mime : _mimeForExtension(ext));
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      if (kIsWeb) const SizedBox(height: 12),
      GoatPremiumCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose file', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'PDF, CSV, XLSX, images (PNG/JPEG/WebP/HEIC) · max 15 MB. Legacy .xls: export to CSV or XLSX first.',
              style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Browse files'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text('Document hint (optional)', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String?>(
        value: _sourceHintDb,
        decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'What is this file?'),
        dropdownColor: GoatTokens.surface,
        style: TextStyle(color: GoatTokens.textPrimary),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text('Auto-detect', style: TextStyle(color: GoatTokens.textPrimary)),
          ),
          DropdownMenuItem(value: 'bank_statement', child: Text('Bank statement', style: TextStyle(color: GoatTokens.textPrimary))),
          DropdownMenuItem(value: 'credit_card_statement', child: Text('Credit card statement', style: TextStyle(color: GoatTokens.textPrimary))),
          DropdownMenuItem(value: 'wallet_statement', child: Text('Wallet / payment export', style: TextStyle(color: GoatTokens.textPrimary))),
          DropdownMenuItem(value: 'upi_receipt', child: Text('UPI / payment receipt', style: TextStyle(color: GoatTokens.textPrimary))),
          DropdownMenuItem(
            value: 'unknown_financial_document',
            child: Text('Unknown — treat as generic', style: TextStyle(color: GoatTokens.textPrimary)),
          ),
        ],
        onChanged: (v) => setState(() => _sourceHintDb = v),
      ),
      const SizedBox(height: 12),
      Text('Account type (optional)', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: _accountType,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        dropdownColor: GoatTokens.surface,
        style: TextStyle(color: GoatTokens.textPrimary),
        items: const [
          DropdownMenuItem(value: 'bank', child: Text('Bank account')),
          DropdownMenuItem(value: 'credit_card', child: Text('Credit card')),
          DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
          DropdownMenuItem(value: 'loan', child: Text('Loan')),
          DropdownMenuItem(value: 'other', child: Text('Other')),
        ],
        onChanged: (v) => setState(() => _accountType = v ?? 'bank'),
      ),
    ];
  }

  List<Widget> _stepPreview() {
    final det = _detection;
    final p = _parse;
    return [
      if (det?.kind == StatementFileKind.xls ||
          det?.kind == StatementFileKind.unsupported ||
          det?.kind == StatementFileKind.image)
        GoatPremiumCard(
          accentBorder: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(det?.note ?? 'Unsupported format.', style: TextStyle(color: GoatTokens.textMuted, height: 1.4)),
              if (det?.kind == StatementFileKind.image) ...[
                const SizedBox(height: 8),
                Text(
                  'We still store the original file and raw layer for reprocessing. Save for review to queue it for OCR or manual handling.',
                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.35),
                ),
              ],
              const SizedBox(height: 12),
              if (det != null && _bytes != null)
                OutlinedButton(
                  onPressed: _saveNeedsReview,
                  child: const Text('Save file for manual review'),
                ),
            ],
          ),
        )
      else if (p != null) ...[
        GoatPremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Preview', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Detected: ${det?.kind.name ?? "—"} · confidence ${p.confidence.toStringAsFixed(0)}%',
                style: TextStyle(color: GoatTokens.textMuted, fontSize: 12),
              ),
              if (p.confidence < 58)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Low confidence — use “Adjust columns” to map date and amount columns.',
                    style: TextStyle(color: const Color(0xFFFBBF24), fontSize: 11, height: 1.35),
                  ),
                ),
              Text('Transactions: ${p.rows.length}', style: TextStyle(color: GoatTokens.gold, fontSize: 13)),
              if (p.periodStart != null && p.periodEnd != null)
                Text(
                  'Period: ${p.periodStart} → ${p.periodEnd}',
                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                ),
              const SizedBox(height: 8),
              ...p.warnings.map((w) => Text('• $w', style: TextStyle(color: const Color(0xFFFCA5A5), fontSize: 11))),
              const SizedBox(height: 8),
              Text('Sample', style: TextStyle(color: GoatTokens.textMuted, fontSize: 11)),
              ...p.rows.take(5).map(
                    (r) => Text(
                      '${r.txnDate.toString().split(' ').first} · ${r.description} · ${r.amount} ${r.direction}',
                      style: TextStyle(color: GoatTokens.textPrimary, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (p.rows.isEmpty && _canParseKind && _bytes != null)
          OutlinedButton(
            onPressed: _saveNeedsReview,
            child: const Text('Nothing parsed — save for manual review'),
          ),
        if (p.rows.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _prefillMappingFields(p.mapping);
                    setState(() => _step = 2);
                  },
                  child: const Text('Adjust columns'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => setState(() => _step = 3),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ],
    ];
  }

  List<Widget> _stepMapping() {
    return [
      GoatPremiumCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Column indices', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              '0-based column numbers in the table header row. Leave blank to use auto-detect for that field.',
              style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.35),
            ),
            const SizedBox(height: 12),
            _mapField('Date', _cDate),
            _mapField('Description', _cDesc),
            _mapField('Debit', _cDebit),
            _mapField('Credit', _cCredit),
            _mapField('Amount', _cAmount),
            _mapField('Balance', _cBalance),
            _mapField('Reference', _cRef),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Back')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _reparseWithMapping, child: const Text('Apply & preview')),
        ],
      ),
    ];
  }

  Widget _mapField(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        style: TextStyle(color: GoatTokens.textPrimary),
      ),
    );
  }

  List<Widget> _stepMode() {
    return [
      GoatPremiumCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import mode', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            RadioListTile<String>(
              title: const Text('Statement-aware Smart'),
              subtitle: const Text('Dedupe against receipts; statement is primary when matched.'),
              value: 'smart',
              groupValue: _importMode,
              onChanged: (v) => setState(() => _importMode = v ?? 'smart'),
            ),
            RadioListTile<String>(
              title: const Text('Statements only lens'),
              subtitle: const Text('For statement-backed analytics views; still stored separately from classic ledger.'),
              value: 'statements_only',
              groupValue: _importMode,
              onChanged: (v) => setState(() => _importMode = v ?? 'smart'),
            ),
            RadioListTile<String>(
              title: const Text('Keep separate / no merge'),
              subtitle: const Text('Store rows only — no dedupe or canonical merge yet.'),
              value: 'keep_separate',
              groupValue: _importMode,
              onChanged: (v) => setState(() => _importMode = v ?? 'smart'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Back')),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => setState(() => _step = 4), child: const Text('Review & commit')),
        ],
      ),
    ];
  }

  List<Widget> _stepConfirm() {
    final p = _parse;
    return [
      Text(
        'You are about to import ${p?.rows.length ?? 0} transactions in $_importMode mode.',
        style: TextStyle(color: GoatTokens.textMuted, height: 1.4),
      ),
      const SizedBox(height: 8),
      Text(
        'Statements lens forecast includes imported debits in the horizon and may overlap recurring bills — check Forecast “Why this number?”.',
        style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.35),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          TextButton(onPressed: () => setState(() => _step = 3), child: const Text('Back')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _commit, child: const Text('Commit import')),
        ],
      ),
    ];
  }

  List<Widget> _stepDone() {
    final r = _result;
    return [
      GoatPremiumCard(
        accentBorder: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _savedReviewOnly ? 'Saved for review' : 'Import complete',
              style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w800),
            ),
            if (_savedReviewOnly) ...[
              const SizedBox(height: 8),
              Text(
                'The file is stored under Import history as needs_review. Finish mapping in a desktop spreadsheet export if needed.',
                style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.35),
              ),
            ],
            if (!_savedReviewOnly && r != null) ...[
              const SizedBox(height: 8),
              Text('Imported: ${r.imported}', style: TextStyle(color: GoatTokens.textPrimary)),
              Text('Skipped (fingerprint dup): ${r.skippedDuplicates}', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
              Text('Linked to documents: ${r.linkedDocuments}', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
              Text('Needs review: ${r.needsReview}', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Done'),
      ),
    ];
  }
}
