import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

/// Idle state — camera, library, uploads, and multi-select.
class ScanIdle extends StatelessWidget {
  const ScanIdle({
    super.key,
    required this.onCamera,
    required this.onPhotoLibrary,
    required this.onUploadPdf,
    required this.onPickMultiple,
    required this.onUploadMultiple,
  });

  final VoidCallback onCamera;
  final VoidCallback onPhotoLibrary;
  final VoidCallback onUploadPdf;
  final VoidCallback onPickMultiple;
  final VoidCallback onUploadMultiple;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onCamera,
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: BillyTheme.zinc950,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: BillyTheme.zinc300.withOpacity(0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.2), width: 4),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Open Camera',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.05,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onPhotoLibrary,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: BillyTheme.zinc100,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.photo_library_rounded, size: 28, color: BillyTheme.zinc950),
                      const SizedBox(height: 12),
                      const Text(
                        'Photo Library',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.02,
                          color: BillyTheme.zinc950,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GestureDetector(
                onTap: onUploadPdf,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: BillyTheme.zinc100,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.picture_as_pdf_rounded, size: 28, color: BillyTheme.zinc950),
                      const SizedBox(height: 12),
                      const Text(
                        'Upload file',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.02,
                          color: BillyTheme.zinc950,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onPickMultiple,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
                  decoration: BoxDecoration(
                    color: BillyTheme.emerald50,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: BillyTheme.emerald100),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.photo_library_outlined, size: 26, color: BillyTheme.emerald700),
                      const SizedBox(height: 8),
                      Text(
                        'Multiple photos',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: BillyTheme.emerald700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Up to 12 at once',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: BillyTheme.zinc400),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: onUploadMultiple,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
                  decoration: BoxDecoration(
                    color: BillyTheme.emerald50,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: BillyTheme.emerald100),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.folder_open_rounded, size: 26, color: BillyTheme.emerald700),
                      const SizedBox(height: 8),
                      Text(
                        'Multiple files',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: BillyTheme.emerald700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Images or PDFs',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: BillyTheme.zinc400),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
