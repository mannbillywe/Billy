import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/extracted_receipt.dart';

class ScanSuccess extends StatelessWidget {
  const ScanSuccess({
    super.key,
    required this.receipt,
    required this.onDiscard,
    required this.onSave,
  });

  final ExtractedReceipt receipt;
  final VoidCallback onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Success badge
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: BillyTheme.zinc100,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: const Icon(Icons.check_circle_rounded, size: 24, color: BillyTheme.zinc950),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Extraction complete', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.02, color: BillyTheme.zinc950)),
                    if (receipt.confidence.isNotEmpty)
                      Text(
                        '${receipt.confidence[0].toUpperCase()}${receipt.confidence.substring(1)} confidence',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BillyTheme.zinc400),
                      ),
                  ],
                ),
              ),
              if (receipt.category != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: BillyTheme.zinc950,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    receipt.category!,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Invoice card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: BillyTheme.zinc100),
            boxShadow: [BoxShadow(color: BillyTheme.zinc100.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: BillyTheme.zinc50,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(40), topRight: Radius.circular(40)),
                  border: Border(bottom: BorderSide(color: BillyTheme.zinc100)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receipt.vendorName,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.05, color: BillyTheme.zinc950),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${receipt.date}${receipt.invoiceNumber != null ? ' • ${receipt.invoiceNumber}' : ''}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.zinc400),
                    ),
                    if (receipt.vendorGstin != null) ...[
                      const SizedBox(height: 4),
                      Text('GSTIN: ${receipt.vendorGstin}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BillyTheme.zinc400)),
                    ],
                  ],
                ),
              ),
              // Line items
              if (receipt.lineItems.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BillyTheme.zinc100))),
                  child: Column(
                    children: receipt.lineItems.map((item) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.description,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.zinc950),
                                  ),
                                  if (item.quantity > 1 || item.hsnCode != null)
                                    Text(
                                      [
                                        if (item.quantity > 1) 'x${item.quantity}',
                                        if (item.hsnCode != null) 'HSN: ${item.hsnCode}',
                                      ].join(' • '),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BillyTheme.zinc400),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              formatter.format(item.total),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.zinc950),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              // Totals
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: BillyTheme.zinc950,
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
                ),
                child: Column(
                  children: [
                    _buildRow('Subtotal', formatter.format(receipt.subtotal)),
                    if (receipt.cgst > 0) ...[
                      const SizedBox(height: 8),
                      _buildRow('CGST', formatter.format(receipt.cgst)),
                    ],
                    if (receipt.sgst > 0) ...[
                      const SizedBox(height: 8),
                      _buildRow('SGST', formatter.format(receipt.sgst)),
                    ],
                    if (receipt.igst > 0) ...[
                      const SizedBox(height: 8),
                      _buildRow('IGST', formatter.format(receipt.igst)),
                    ],
                    if (receipt.cgst == 0 && receipt.sgst == 0 && receipt.igst == 0 && receipt.tax > 0) ...[
                      const SizedBox(height: 8),
                      _buildRow('Tax', formatter.format(receipt.tax)),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.only(top: 16),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: BillyTheme.zinc800))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.05, color: Colors.white)),
                          Text(formatter.format(receipt.total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.05, color: Colors.white)),
                        ],
                      ),
                    ),
                    if (receipt.paymentMethod != null || receipt.paymentStatus != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (receipt.paymentMethod != null)
                            Text(receipt.paymentMethod!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BillyTheme.zinc400)),
                          if (receipt.paymentStatus != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: receipt.paymentStatus == 'Paid' ? Colors.white.withValues(alpha: 0.1) : BillyTheme.red400.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                receipt.paymentStatus!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: receipt.paymentStatus == 'Paid' ? BillyTheme.zinc300 : BillyTheme.red400,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Actions
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onDiscard,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(color: BillyTheme.zinc100, borderRadius: BorderRadius.circular(999)),
                  alignment: Alignment.center,
                  child: const Text('Discard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.02, color: BillyTheme.zinc950)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: onSave,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: BillyTheme.zinc950,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [BoxShadow(color: BillyTheme.zinc300.withValues(alpha: 0.5), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  alignment: Alignment.center,
                  child: const Text('Save Invoice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.02, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.zinc400)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.zinc400)),
      ],
    );
  }
}
