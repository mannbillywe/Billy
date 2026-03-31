import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

class OcrBanner extends StatelessWidget {
  const OcrBanner({super.key, this.onScan});

  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray50),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BillyTheme.emerald50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.document_scanner_outlined, size: 24, color: BillyTheme.emerald600),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'OCR Features',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
                ),
                SizedBox(height: 2),
                Text(
                  'OCR and serialization of bills',
                  style: TextStyle(fontSize: 12, color: BillyTheme.gray500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onScan,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: BillyTheme.emerald600,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Scan Bill',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
