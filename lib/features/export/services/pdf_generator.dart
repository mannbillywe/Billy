import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/formatting/app_currency.dart';
import '../models/export_document.dart';

/// Generates PDF reports for Billy export
class PdfGenerator {
  PdfGenerator();

  final _dateFormat = DateFormat('dd MMM yyyy');

  Future<Uint8List> generateReport({
    required List<ExportDocument> documents,
    required DateTime startDate,
    required DateTime endDate,
    String? currencyCode,
  }) async {
    final currencyFormat = AppCurrency.formatter(currencyCode);
    final pdf = pw.Document();
    final total = documents.fold<double>(0, (sum, d) => sum + d.amount);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Billy',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Expense Report • ${_dateFormat.format(startDate)} – ${_dateFormat.format(endDate)}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey300,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total Expenses', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text(currencyFormat.format(total), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Text('Transactions', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400),
    columnWidths: {
      0: const pw.FlexColumnWidth(3),
      1: const pw.FlexColumnWidth(1.5),
      2: const pw.FlexColumnWidth(1.5),
      3: const pw.FlexColumnWidth(1.5),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text('Vendor', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text('Category', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
      ...documents.map((d) => pw.TableRow(
        children: [
          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(d.vendorName)),
          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_dateFormat.format(d.date))),
          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(d.category)),
          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(currencyFormat.format(d.amount))),
        ],
      )),
    ],
  ),
        ],
      ),
    );

    return pdf.save();
  }
}
