import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

class OcrBanner extends StatelessWidget {
  const OcrBanner({super.key, this.onManualEntry});

  /// Opens manual expense entry (FAB opens scan / camera).
  final VoidCallback? onManualEntry;

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
            child: const Icon(Icons.edit_note_rounded, size: 24, color: BillyTheme.emerald600),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Manual entry',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
                ),
                SizedBox(height: 2),
                Text(
                  'Add an expense without scanning a bill',
                  style: TextStyle(fontSize: 12, color: BillyTheme.gray500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onManualEntry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: BillyTheme.emerald600,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Enter manually',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
