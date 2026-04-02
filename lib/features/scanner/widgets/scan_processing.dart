import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

/// Processing state while Gemini reads the scan.
class ScanProcessing extends StatelessWidget {
  const ScanProcessing({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
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
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(BillyTheme.zinc400),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Extracting',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.05,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Google Gemini · extracting fields',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: BillyTheme.zinc400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
