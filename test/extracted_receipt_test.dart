import 'package:billy/features/scanner/models/extracted_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExtractedReceipt.fromJson', () {
    test('uses explicit CGST+SGST+IGST for tax, not double gst field', () {
      final r = ExtractedReceipt.fromJson({
        'vendor_name': 'Acme',
        'invoice_date': '2024-01-02',
        'line_items': <dynamic>[],
        'subtotal': 100,
        'cgst': 9,
        'sgst': 9,
        'igst': 0,
        'gst': 999,
        'tax': 999,
        'total_amount': 118,
      });
      expect(r.tax, closeTo(18.0, 0.001));
      expect(r.cgst, 9);
      expect(r.sgst, 9);
    });

    test('falls back to gst+tax when no CGST/SGST/IGST', () {
      final r = ExtractedReceipt.fromJson({
        'vendor_name': 'X',
        'line_items': <dynamic>[],
        'gst': 5,
        'tax': 3,
        'total': 108,
      });
      expect(r.tax, closeTo(8.0, 0.001));
    });

    test('unwraps first invoice from invoices list', () {
      final r = ExtractedReceipt.fromJson({
        'invoices': [
          {
            'vendor_name': 'Nested',
            'line_items': <dynamic>[],
            'total_amount': 50,
          },
        ],
      });
      expect(r.vendorName, 'Nested');
      expect(r.total, closeTo(50.0, 0.001));
    });

    test('parses currency-like total string', () {
      final r = ExtractedReceipt.fromJson({
        'vendor_name': 'Y',
        'line_items': <dynamic>[],
        'total_amount': '₹1,234.50',
      });
      expect(r.total, closeTo(1234.5, 0.001));
    });
  });

  group('ExtractedReceipt.fromInvoiceOcr', () {
    test('splits total_tax into CGST/SGST when IGST zero', () {
      final r = ExtractedReceipt.fromInvoiceOcr(
        {
          'vendor_name': 'Shop',
          'invoice_date': '2024-06-01T00:00:00Z',
          'subtotal': 100.0,
          'total_tax': 18.0,
          'total': 118.0,
          'currency': 'INR',
        },
        <Map<String, dynamic>>[],
      );
      expect(r.cgst + r.sgst + r.igst, closeTo(18.0, 0.01));
      expect(r.tax, closeTo(18.0, 0.01));
    });
  });

  group('LineItem.fromJson', () {
    test('reads amount or total', () {
      final a = LineItem.fromJson({'description': 'A', 'amount': 10.0});
      expect(a.total, 10.0);
      final b = LineItem.fromJson({'description': 'B', 'total': 7.5});
      expect(b.total, 7.5);
    });
  });
}
