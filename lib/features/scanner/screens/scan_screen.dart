import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/logging/billy_logger.dart';
import '../../../core/theme/billy_theme.dart';
import '../../invoices/services/invoice_ocr_pipeline.dart';
import '../models/extracted_receipt.dart';
import '../widgets/scan_error.dart';
import '../widgets/scan_idle.dart';
import '../widgets/scan_processing.dart';
import '../widgets/scan_review_panel.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  ScanState _state = ScanState.idle;
  ExtractedReceipt? _extracted;
  String? _invoiceId;
  String? _errorMessage;
  bool _extractInFlight = false;

  String _mimeTypeForPath(String name) {
    final p = name.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.gif')) return 'image/gif';
    if (p.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }

  Future<void> _runPipeline({
    required List<int> bytes,
    required String fileName,
    required String mime,
    required String source,
  }) async {
    if (_extractInFlight) return;
    setState(() {
      _extractInFlight = true;
      _state = ScanState.processing;
      _errorMessage = null;
    });
    try {
      final result = await InvoiceOcrPipeline.uploadAndProcess(
        bytes: Uint8List.fromList(bytes),
        fileName: fileName,
        mimeType: mime,
        source: source,
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

  /// Camera / gallery — image only (compressed).
  Future<void> _pickAndExtract(ImageSource source) async {
    if (_extractInFlight) return;
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
    await _runPipeline(bytes: bytes, fileName: file.name, mime: mime, source: src);
  }

  Future<void> _pickFromGallery() => _pickAndExtract(ImageSource.gallery);
  Future<void> _openCamera() => _pickAndExtract(ImageSource.camera);

  /// PDF / image file (desktop & mobile).
  Future<void> _pickFile() async {
    if (_extractInFlight) return;
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _state = ScanState.error;
        _errorMessage = 'Could not read file bytes';
      });
      return;
    }
    final name = f.name;
    final mime = _mimeTypeForPath(name);
    await _runPipeline(bytes: bytes, fileName: name, mime: mime, source: 'file');
  }

  void _discard() {
    setState(() {
      _state = ScanState.idle;
      _extracted = null;
      _invoiceId = null;
      _errorMessage = null;
    });
  }

  void _onSaveDone() {
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
                  onUploadPdf: _extractInFlight ? () {} : _pickFile,
                ),
              ScanState.processing => const ScanProcessing(key: ValueKey('processing')),
              ScanState.success => ScanReviewPanel(
                  key: const ValueKey('review'),
                  initialReceipt: _extracted!,
                  invoiceId: _invoiceId,
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

enum ScanState { idle, processing, success, error }
