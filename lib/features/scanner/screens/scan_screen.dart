import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/logging/billy_logger.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/documents_provider.dart';
import '../../../services/supabase_service.dart';
import '../models/extracted_receipt.dart';
import '../services/gemini_extractor.dart';
import '../widgets/scan_idle.dart';
import '../widgets/scan_processing.dart';
import '../widgets/scan_success.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  ScanState _state = ScanState.idle;
  ExtractedReceipt? _extracted;

  Future<void> _pickAndExtract(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      imageQuality: 85,
    );

    if (file == null) return;

    setState(() => _state = ScanState.processing);

    try {
      final bytes = await file.readAsBytes();
      final userKey = await SupabaseService.getGeminiApiKey();
      BillyLogger.info('Using ${userKey != null ? "user API key" : "default API key"}');
      final extractor = GeminiExtractor(apiKey: userKey);
      final receipt = await extractor.extractFromImage(bytes);

      if (!mounted) return;
      setState(() {
        _state = ScanState.success;
        _extracted = receipt;
      });
    } catch (e, stack) {
      BillyLogger.extractionFailed(e, stack);
      if (!mounted) return;
      final errStr = e.toString().toLowerCase();
      final isRateLimit = errStr.contains('429') ||
          errStr.contains('rate limit') ||
          errStr.contains('quota') ||
          errStr.contains('resource exhausted') ||
          errStr.contains('too many requests');

      setState(() {
        _state = ScanState.success;
        _extracted = ExtractedReceipt(
          vendorName: isRateLimit
              ? 'Rate limit hit – try again later'
              : 'Extraction failed',
          date: DateTime.now().toIso8601String().substring(0, 10),
          lineItems: [],
          subtotal: 0,
          tax: 0,
          total: 0,
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRateLimit
                  ? 'API rate limit hit. Wait a few minutes or add your own API key in Profile → Settings.'
                  : 'Extraction failed: ${e.toString().split('\n').first}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            backgroundColor: BillyTheme.red500,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    }
  }

  Future<void> _pickFromGallery() => _pickAndExtract(ImageSource.gallery);
  Future<void> _openCamera() => _pickAndExtract(ImageSource.camera);

  void _discard() {
    setState(() {
      _state = ScanState.idle;
      _extracted = null;
    });
  }

  Future<void> _save() async {
    if (_extracted == null) return;
    final r = _extracted!;

    try {
      await ref.read(documentsProvider.notifier).addDocument(
        vendorName: r.vendorName,
        amount: r.total,
        taxAmount: r.tax,
        date: r.date.isNotEmpty ? r.date : DateTime.now().toIso8601String().substring(0, 10),
        type: 'receipt',
        description: r.category ?? r.lineItems.map((e) => e.description).join(', '),
        paymentMethod: r.paymentMethod,
        extractedData: r.toJson(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Receipt saved!', style: TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: BillyTheme.emerald600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      _discard();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e', style: const TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: BillyTheme.red500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }
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
                  onCamera: _openCamera,
                  onPhotoLibrary: _pickFromGallery,
                  onUploadPdf: _pickFromGallery,
                ),
              ScanState.processing => const ScanProcessing(key: ValueKey('processing')),
              ScanState.success => ScanSuccess(
                  key: const ValueKey('success'),
                  receipt: _extracted!,
                  onDiscard: _discard,
                  onSave: _save,
                ),
            },
          ),
        ],
      ),
    );
  }
}

enum ScanState { idle, processing, success }
