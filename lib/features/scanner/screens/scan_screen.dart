import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/logging/billy_logger.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/usage_limits_provider.dart';
import '../../../services/supabase_service.dart';
import '../../invoices/services/invoice_ocr_pipeline.dart';
import '../models/extracted_receipt.dart';
import '../utils/scan_raster_adjust.dart';
import '../widgets/scan_adjust_preview.dart';
import '../widgets/scan_error.dart';
import '../widgets/scan_idle.dart';
import '../widgets/scan_processing.dart';
import '../widgets/scan_review_panel.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _BatchPick {
  const _BatchPick({
    required this.bytes,
    required this.fileName,
    required this.mime,
    required this.source,
  });
  final Uint8List bytes;
  final String fileName;
  final String mime;
  final String source;
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  ScanState _state = ScanState.idle;
  ExtractedReceipt? _extracted;
  String? _invoiceId;
  String? _errorMessage;
  bool _extractInFlight = false;
  Uint8List? _previewBytes;
  String? _previewFileName;
  String? _previewMime;
  String? _previewSource;

  /// When non-null, [onSaveDone] advances to the next scan or closes.
  List<_BatchPick>? _batchQueue;
  int _batchIndex = 0;
  static const int _maxBatch = 12;

  /// Bytes used when background prefetch started (compare on Continue).
  Uint8List? _prefetchSeedBytes;
  Future<void>? _prefetchJob;
  bool _prefetchCancelled = false;
  String? _prefetchedInvoiceId;
  ExtractedReceipt? _prefetchedReceipt;

  static const _minProcessingAnimation = Duration(milliseconds: 720);

  String _mimeTypeForPath(String name) {
    final p = name.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.gif')) return 'image/gif';
    if (p.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }

  Future<({String invoiceId, ExtractedReceipt receipt})> _ocrUploadAndProcess({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String source,
    required bool countTowardOcrLimit,
  }) async {
    if (countTowardOcrLimit) {
      await SupabaseService.incrementOcrScan();
      ref.invalidate(usageLimitsProvider);
    }
    return InvoiceOcrPipeline.uploadAndProcess(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      source: source,
    );
  }

  /// Runs while user rotates/adjusts — same bytes as initial preview when they tap Continue.
  Future<void> _prefetchDuringAdjust() async {
    if (_previewBytes == null ||
        _previewFileName == null ||
        _previewMime == null ||
        _previewSource == null) {
      return;
    }
    final seed = Uint8List.fromList(_previewBytes!);
    final fn = _previewFileName!;
    final mime = _previewMime!;
    final src = _previewSource!;
    _prefetchSeedBytes = seed;
    _prefetchedInvoiceId = null;
    _prefetchedReceipt = null;

    try {
      final result = await _ocrUploadAndProcess(
        bytes: seed,
        fileName: fn,
        mimeType: mime,
        source: src,
        countTowardOcrLimit: true,
      );
      if (!mounted || _prefetchCancelled) {
        await SupabaseService.deleteInvoiceForUser(result.invoiceId);
        return;
      }
      _prefetchedInvoiceId = result.invoiceId;
      _prefetchedReceipt = result.receipt;
    } catch (e, stack) {
      BillyLogger.warn('Background OCR during adjust failed', '$e\n$stack');
    }
  }

  void _schedulePrefetchAfterAdjustFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _state != ScanState.previewAdjust) return;
      _prefetchCancelled = false;
      _prefetchJob = _prefetchDuringAdjust();
    });
  }

  Future<void> _runPipelineDirect({
    required List<int> bytes,
    required String fileName,
    required String mime,
    required String source,
    bool partOfBatch = false,
  }) async {
    if (_extractInFlight) return;
    if (!partOfBatch) {
      _batchQueue = null;
      _batchIndex = 0;
    }
    _extractInFlight = true;
    setState(() {
      _state = ScanState.processing;
      _errorMessage = null;
      _previewBytes = null;
      _previewFileName = null;
      _previewMime = null;
      _previewSource = null;
      _clearPrefetchState();
    });
    try {
      final result = await _ocrUploadAndProcess(
        bytes: Uint8List.fromList(bytes),
        fileName: fileName,
        mimeType: mime,
        source: source,
        countTowardOcrLimit: true,
      );
      if (!mounted) return;
      setState(() {
        _extractInFlight = false;
        _state = ScanState.success;
        _extracted = result.receipt;
        _invoiceId = result.invoiceId;
      });
    } catch (e, stack) {
      BillyLogger.extractionFailed(e, stack);
      if (!mounted) return;
      setState(() {
        _extractInFlight = false;
        _state = ScanState.error;
        _errorMessage = e.toString().split('\n').first;
      });
    }
  }

  Future<void> _onContinueFromAdjust(
    Uint8List bytes,
    String fileName,
    String mime,
    String source,
  ) async {
    if (_extractInFlight) return;
    _extractInFlight = true;
    setState(() {
      _state = ScanState.processing;
      _errorMessage = null;
    });

    final minUi = Future<void>.delayed(_minProcessingAnimation);
    final sameAsPrefetchSeed = _prefetchSeedBytes != null &&
        _prefetchSeedBytes!.length == bytes.length &&
        listEquals(_prefetchSeedBytes!, bytes);

    try {
      if (sameAsPrefetchSeed) {
        await Future.wait([minUi, _prefetchJob ?? Future.value()]);
        if (!mounted) return;
        if (_prefetchCancelled) {
          setState(() {
            _extractInFlight = false;
            _state = ScanState.idle;
          });
          return;
        }
        if (_prefetchedReceipt != null && _prefetchedInvoiceId != null) {
          setState(() {
            _extractInFlight = false;
            _state = ScanState.success;
            _extracted = _prefetchedReceipt;
            _invoiceId = _prefetchedInvoiceId;
          });
          _clearPrefetchState();
          return;
        }
        // Prefetch failed: retry same image without charging OCR twice.
        try {
          final result = await _ocrUploadAndProcess(
            bytes: bytes,
            fileName: fileName,
            mimeType: mime,
            source: source,
            countTowardOcrLimit: false,
          );
          if (!mounted) return;
          setState(() {
            _extractInFlight = false;
            _state = ScanState.success;
            _extracted = result.receipt;
            _invoiceId = result.invoiceId;
          });
          _clearPrefetchState();
          return;
        } catch (e, stack) {
          BillyLogger.extractionFailed(e, stack);
          if (!mounted) return;
          setState(() {
            _extractInFlight = false;
            _state = ScanState.error;
            _errorMessage = e.toString().split('\n').first;
          });
          _clearPrefetchState();
          return;
        }
      }

      // User changed the image (e.g. rotate) — stop prefetch, remove any partial invoice, re-run OCR.
      _prefetchCancelled = true;
      try {
        await _prefetchJob;
      } catch (_) {}
      if (_prefetchedInvoiceId != null) {
        await SupabaseService.deleteInvoiceForUser(_prefetchedInvoiceId!);
      }
      _clearPrefetchState();
      await minUi;
      if (!mounted) return;

      final result = await _ocrUploadAndProcess(
        bytes: bytes,
        fileName: fileName,
        mimeType: mime,
        source: source,
        countTowardOcrLimit: true,
      );
      if (!mounted) return;
      setState(() {
        _extractInFlight = false;
        _state = ScanState.success;
        _extracted = result.receipt;
        _invoiceId = result.invoiceId;
      });
    } catch (e, stack) {
      BillyLogger.extractionFailed(e, stack);
      if (!mounted) return;
      setState(() {
        _extractInFlight = false;
        _state = ScanState.error;
        _errorMessage = e.toString().split('\n').first;
      });
    } finally {
      _extractInFlight = false;
      _clearPrefetchState();
    }
  }

  void _clearPrefetchState() {
    _prefetchSeedBytes = null;
    _prefetchJob = null;
    _prefetchedInvoiceId = null;
    _prefetchedReceipt = null;
  }

  Future<void> _startBatch(List<_BatchPick> items) async {
    if (items.isEmpty || _extractInFlight) return;
    if (items.length > _maxBatch) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Choose at most $_maxBatch files at once.')),
      );
      return;
    }
    _batchQueue = items;
    _batchIndex = 0;
    final first = items.first;
    await _runPipelineDirect(
      bytes: first.bytes,
      fileName: first.fileName,
      mime: first.mime,
      source: first.source,
      partOfBatch: true,
    );
  }

  Future<void> _pickMultipleFromGallery() async {
    if (_extractInFlight) return;
    if (kIsWeb) {
      await _pickFiles(allowMultiple: true);
      return;
    }
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (files.isEmpty) return;
    if (files.length > _maxBatch) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Choose at most $_maxBatch photos at once.')),
      );
      return;
    }
    final items = <_BatchPick>[];
    for (final f in files) {
      final b = await f.readAsBytes();
      items.add(_BatchPick(
        bytes: Uint8List.fromList(b),
        fileName: f.name,
        mime: _mimeTypeForPath(f.name),
        source: 'gallery',
      ));
    }
    await _startBatch(items);
  }

  /// Camera / gallery — image only (compressed).
  Future<void> _pickAndExtract(ImageSource source) async {
    if (_extractInFlight) return;
    _batchQueue = null;
    _batchIndex = 0;
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final mime = _mimeTypeForPath(file.name);
    final src = source == ImageSource.camera ? 'camera' : 'gallery';
    if (isAdjustableRasterMime(mime)) {
      if (!mounted) return;
      setState(() {
        _state = ScanState.previewAdjust;
        _previewBytes = Uint8List.fromList(bytes);
        _previewFileName = file.name;
        _previewMime = mime;
        _previewSource = src;
      });
      _schedulePrefetchAfterAdjustFrame();
    } else {
      await _runPipelineDirect(bytes: bytes, fileName: file.name, mime: mime, source: src);
    }
  }

  Future<void> _pickFromGallery() => _pickAndExtract(ImageSource.gallery);
  Future<void> _openCamera() => _pickAndExtract(ImageSource.camera);

  /// PDF / image file (desktop & mobile). [allowMultiple] queues several scans in one go.
  Future<void> _pickFiles({bool allowMultiple = false}) async {
    if (_extractInFlight) return;
    if (!allowMultiple) {
      _batchQueue = null;
      _batchIndex = 0;
    }
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
      allowMultiple: allowMultiple,
    );
    if (res == null || res.files.isEmpty) return;
    final raw = res.files.where((f) => f.bytes != null && f.bytes!.isNotEmpty).toList();
    if (raw.isEmpty) {
      setState(() {
        _state = ScanState.error;
        _errorMessage = 'Could not read file bytes';
      });
      return;
    }
    if (allowMultiple) {
      if (raw.length > _maxBatch) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Choose at most $_maxBatch files at once.')),
        );
        return;
      }
      final items = <_BatchPick>[];
      for (final f in raw) {
        final bytes = f.bytes!;
        final name = f.name;
        final mime = _mimeTypeForPath(name);
        items.add(_BatchPick(
          bytes: Uint8List.fromList(bytes),
          fileName: name,
          mime: mime,
          source: 'file',
        ));
      }
      await _startBatch(items);
      return;
    }

    final f = raw.first;
    final bytes = f.bytes!;
    final name = f.name;
    final mime = _mimeTypeForPath(name);
    if (mime == 'application/pdf') {
      await _runPipelineDirect(bytes: bytes, fileName: name, mime: mime, source: 'file');
    } else if (isAdjustableRasterMime(mime)) {
      if (!mounted) return;
      setState(() {
        _state = ScanState.previewAdjust;
        _previewBytes = Uint8List.fromList(bytes);
        _previewFileName = name;
        _previewMime = mime;
        _previewSource = 'file';
      });
      _schedulePrefetchAfterAdjustFrame();
    } else {
      await _runPipelineDirect(bytes: bytes, fileName: name, mime: mime, source: 'file');
    }
  }

  void _discard() {
    unawaited(_performDiscard());
  }

  Future<void> _performDiscard() async {
    _batchQueue = null;
    _batchIndex = 0;
    _prefetchCancelled = true;
    try {
      await _prefetchJob;
    } catch (_) {}
    if (_prefetchedInvoiceId != null) {
      try {
        await SupabaseService.deleteInvoiceForUser(_prefetchedInvoiceId!);
      } catch (e) {
        BillyLogger.warn('discard: delete prefetch invoice failed', e);
      }
    }
    final inv = _invoiceId;
    if (inv != null && _state == ScanState.success) {
      try {
        await SupabaseService.deleteInvoiceForUser(inv);
      } catch (e) {
        BillyLogger.warn('discard: delete invoice failed', e);
      }
    }
    if (!mounted) return;
    setState(() {
      _state = ScanState.idle;
      _extracted = null;
      _invoiceId = null;
      _errorMessage = null;
      _previewBytes = null;
      _previewFileName = null;
      _previewMime = null;
      _previewSource = null;
      _extractInFlight = false;
      _clearPrefetchState();
    });
  }

  void _onSaveDone() {
    final q = _batchQueue;
    if (q != null && _batchIndex < q.length - 1) {
      final next = _batchIndex + 1;
      final item = q[next];
      _batchIndex = next;
      unawaited(_runPipelineDirect(
        bytes: item.bytes,
        fileName: item.fileName,
        mime: item.mime,
        source: item.source,
        partOfBatch: true,
      ));
      return;
    }
    _batchQueue = null;
    _batchIndex = 0;
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scan.',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.05,
                  color: BillyTheme.zinc950,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Digitize receipts instantly.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 18,
                  color: BillyTheme.zinc400,
                ),
          ),
          const SizedBox(height: 32),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: switch (_state) {
              ScanState.idle => ScanIdle(
                  key: const ValueKey('idle'),
                  onCamera: _extractInFlight ? () {} : _openCamera,
                  onPhotoLibrary: _extractInFlight ? () {} : _pickFromGallery,
                  onUploadPdf: _extractInFlight ? () {} : () => _pickFiles(allowMultiple: false),
                  onPickMultiple: _extractInFlight ? () {} : _pickMultipleFromGallery,
                  onUploadMultiple: _extractInFlight ? () {} : () => _pickFiles(allowMultiple: true),
                ),
              ScanState.previewAdjust => ScanAdjustPreview(
                  key: const ValueKey('preview'),
                  initialBytes: _previewBytes!,
                  fileName: _previewFileName!,
                  mimeType: _previewMime!,
                  source: _previewSource!,
                  onContinue: (b, fn, m, s) {
                    _onContinueFromAdjust(b, fn, m, s);
                  },
                  onRetake: _discard,
                ),
              ScanState.processing => const ScanProcessing(key: ValueKey('processing')),
              ScanState.success => ScanReviewPanel(
                  key: ValueKey('review_${_invoiceId ?? _batchIndex}'),
                  initialReceipt: _extracted!,
                  invoiceId: _invoiceId,
                  batchLabel: _batchQueue != null && _batchQueue!.length > 1
                      ? '${_batchIndex + 1} of ${_batchQueue!.length}'
                      : null,
                  onDiscard: _discard,
                  onDone: _onSaveDone,
                ),
              ScanState.error => ScanError(
                  key: const ValueKey('error'),
                  message: _errorMessage ?? 'Something went wrong',
                  onRetry: _discard,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
            },
          ),
        ],
      ),
    );
  }
}

enum ScanState { idle, previewAdjust, processing, success, error }
