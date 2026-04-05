import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';
import '../utils/scan_raster_adjust.dart';

/// Pre-OCR step: rotate camera/gallery/file images before sending to the pipeline.
class ScanAdjustPreview extends StatefulWidget {
  const ScanAdjustPreview({
    super.key,
    required this.initialBytes,
    required this.fileName,
    required this.mimeType,
    required this.source,
    required this.onContinue,
    required this.onRetake,
  });

  final Uint8List initialBytes;
  final String fileName;
  final String mimeType;
  final String source;
  final void Function(Uint8List bytes, String fileName, String mimeType, String source) onContinue;
  final VoidCallback onRetake;

  @override
  State<ScanAdjustPreview> createState() => _ScanAdjustPreviewState();
}

class _ScanAdjustPreviewState extends State<ScanAdjustPreview> {
  late Uint8List _bytes;
  late String _fileName;

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
    _fileName = widget.fileName;
  }

  void _rotate(bool clockwise) {
    final out = rotateRaster90(_bytes, clockwise: clockwise);
    if (out == null) return;
    setState(() {
      _bytes = out;
      _fileName = jpegFileName(_fileName);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Adjust scan',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: BillyTheme.zinc950,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Rotate if needed. Extraction runs in the background — when you continue, we show progress (often almost instant).',
          style: TextStyle(fontSize: 14, color: BillyTheme.zinc400),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 1,
            child: Image.memory(
              _bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _rotate(false),
                icon: const Icon(Icons.rotate_left_rounded),
                label: const Text('Rotate left'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _rotate(true),
                icon: const Icon(Icons.rotate_right_rounded),
                label: const Text('Rotate right'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => widget.onContinue(_bytes, _fileName, 'image/jpeg', widget.source),
          style: FilledButton.styleFrom(
            backgroundColor: BillyTheme.emerald600,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Yes, extract'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: widget.onRetake,
          child: const Text('Choose another file'),
        ),
      ],
    );
  }
}
