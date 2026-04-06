import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'statement_tabular_engine.dart';

/// Extracts text from digital PDFs for the same tabular pipeline (deterministic layout is best-effort).
class StatementPdfTextService {
  StatementPdfTextService._();

  static Future<({List<List<String>> grid, bool hasText})> extractGrid(Uint8List bytes) async {
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openData(bytes);
      final buf = StringBuffer();
      for (var i = 0; i < doc.pages.length; i++) {
        final page = doc.pages[i];
        final tr = await page.loadText();
        buf.writeln(tr?.fullText ?? '');
      }
      final text = buf.toString().trim();
      if (text.length < 20) {
        return (grid: <List<String>>[], hasText: false);
      }
      final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
      final grid = <List<String>>[];
      for (final line in lines) {
        final cells = line.split(RegExp(r'\s{2,}|\t')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        if (cells.length >= 2) {
          grid.add(cells);
        }
      }
      return (grid: grid, hasText: true);
    } catch (_) {
      return (grid: <List<String>>[], hasText: false);
    } finally {
      await doc?.dispose();
    }
  }

  static Future<StatementParseOutcome> parsePdf(Uint8List bytes) async {
    final g = await extractGrid(bytes);
    if (!g.hasText || g.grid.length < 2) {
      return StatementParseOutcome(
        rows: [],
        confidence: 10,
        mapping: const ColumnMapping(),
        warnings: ['No extractable text — export CSV or use a digital statement.'],
      );
    }
    return StatementTabularEngine.parseGrid(g.grid);
  }
}
