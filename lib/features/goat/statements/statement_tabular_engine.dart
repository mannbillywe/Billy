import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import 'statement_xlsx_reader.dart';

/// Detected source type for [statement_imports.source_type].
enum StatementFileKind {
  pdfDigital,
  pdfScanned,
  csv,
  xls,
  xlsx,
  unsupported,
}

class StatementFormatDetection {
  const StatementFormatDetection({
    required this.kind,
    required this.confidence,
    this.note,
  });

  final StatementFileKind kind;
  final double confidence;
  final String? note;
}

class ColumnMapping {
  const ColumnMapping({
    this.dateCol,
    this.descriptionCol,
    this.debitCol,
    this.creditCol,
    this.amountCol,
    this.balanceCol,
    this.referenceCol,
  });

  final int? dateCol;
  final int? descriptionCol;
  final int? debitCol;
  final int? creditCol;
  final int? amountCol;
  final int? balanceCol;
  final int? referenceCol;

  bool get hasMinimum => dateCol != null && (amountCol != null || debitCol != null || creditCol != null);
}

class ParsedStatementTxn {
  ParsedStatementTxn({
    required this.rowIndex,
    required this.txnDate,
    required this.description,
    required this.amount,
    required this.direction,
    this.balance,
    this.reference,
  });

  final int rowIndex;
  final DateTime txnDate;
  final String description;
  final double amount;
  final String direction;
  final double? balance;
  final String? reference;
}

class StatementParseOutcome {
  StatementParseOutcome({
    required this.rows,
    required this.confidence,
    required this.mapping,
    this.institutionHint,
    this.periodStart,
    this.periodEnd,
    this.openingBalance,
    this.closingBalance,
    this.warnings = const [],
  });

  final List<ParsedStatementTxn> rows;
  final double confidence;
  final ColumnMapping mapping;
  final String? institutionHint;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final double? openingBalance;
  final double? closingBalance;
  final List<String> warnings;
}

class StatementTabularEngine {
  StatementTabularEngine._();

  static const _maxUploadBytes = 15 * 1024 * 1024;

  static int get maxUploadBytes => _maxUploadBytes;

  static bool isLikelyTextPdf(Uint8List bytes) {
    if (bytes.length < 5) return false;
    final head = String.fromCharCodes(bytes.sublist(0, 5.clamp(0, bytes.length)));
    return head.startsWith('%PDF');
  }

  static bool isZipXlsx(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x50 && bytes[1] == 0x4b;
  }

  static StatementFormatDetection detect({
    required String fileName,
    required String? mimeType,
    required Uint8List bytes,
  }) {
    final nameParts = fileName.toLowerCase().split('.');
    final ext = nameParts.length > 1 ? nameParts.last : '';
    if (bytes.length > _maxUploadBytes) {
      return const StatementFormatDetection(kind: StatementFileKind.unsupported, confidence: 0, note: 'File exceeds 15 MB limit.');
    }
    if (ext == 'csv' || mimeType == 'text/csv' || mimeType == 'text/plain') {
      return const StatementFormatDetection(kind: StatementFileKind.csv, confidence: 95);
    }
    if (ext == 'xlsx' || mimeType == 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
      if (isZipXlsx(bytes)) {
        return const StatementFormatDetection(kind: StatementFileKind.xlsx, confidence: 95);
      }
      return StatementFormatDetection(kind: StatementFileKind.unsupported, confidence: 20, note: 'xlsx zip signature missing');
    }
    if (ext == 'xls' || mimeType == 'application/vnd.ms-excel') {
      return const StatementFormatDetection(
        kind: StatementFileKind.xls,
        confidence: 40,
        note: 'Legacy .xls is not parsed in-app. Export as CSV or xlsx.',
      );
    }
    if (ext == 'pdf' || mimeType == 'application/pdf') {
      if (!isLikelyTextPdf(bytes)) {
        return const StatementFormatDetection(kind: StatementFileKind.pdfScanned, confidence: 35, note: 'Not a PDF header');
      }
      return const StatementFormatDetection(kind: StatementFileKind.pdfDigital, confidence: 70);
    }
    if (isLikelyTextPdf(bytes)) {
      return const StatementFormatDetection(kind: StatementFileKind.pdfDigital, confidence: 60);
    }
    if (isZipXlsx(bytes)) {
      return const StatementFormatDetection(kind: StatementFileKind.xlsx, confidence: 80, note: 'Detected xlsx by signature');
    }
    return const StatementFormatDetection(kind: StatementFileKind.unsupported, confidence: 10);
  }

  static List<List<String>> gridFromBytes(StatementFileKind kind, Uint8List bytes) {
    switch (kind) {
      case StatementFileKind.csv:
        final text = utf8.decode(bytes, allowMalformed: true);
        return const CsvToListConverter().convert(text).map((r) => r.map((e) => e.toString()).toList()).toList();
      case StatementFileKind.xlsx:
        return StatementXlsxReader.readFirstSheet(bytes);
      case StatementFileKind.pdfDigital:
      case StatementFileKind.pdfScanned:
      case StatementFileKind.xls:
      case StatementFileKind.unsupported:
        return [];
    }
  }

  static final _dateHeaders = {'date', 'txn date', 'transaction date', 'posting date', 'value date', 'tran date'};
  static final _descHeaders = {'description', 'particulars', 'narration', 'details', 'merchant', 'payee', 'remarks'};
  static final _debitHeaders = {'debit', 'withdrawal', 'dr', 'money out', 'paid out'};
  static final _creditHeaders = {'credit', 'deposit', 'cr', 'money in', 'paid in'};
  static final _amountHeaders = {'amount', 'transaction amount', 'txn amount'};
  static final _balHeaders = {'balance', 'closing balance', 'available balance', 'running balance'};
  static final _refHeaders = {'reference', 'ref', 'cheque', 'utr', 'rrn', 'txn id', 'transaction id'};

  static int? _matchHeader(List<String> headers, Set<String> keys) {
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase().trim();
      for (final k in keys) {
        if (h == k || h.contains(k)) return i;
      }
    }
    return null;
  }

  static ColumnMapping inferMapping(List<List<String>> grid) {
    if (grid.isEmpty) return const ColumnMapping();
    List<String> headers = [];
    for (var r = 0; r < grid.length.clamp(0, 30); r++) {
      final row = grid[r].map((e) => e.trim()).toList();
      if (row.isEmpty) continue;
      final joined = row.join(' ').toLowerCase();
      if (_dateHeaders.any(joined.contains) && (_amountHeaders.any(joined.contains) || _debitHeaders.any(joined.contains))) {
        headers = row;
        break;
      }
    }
    if (headers.isEmpty) {
      headers = grid.first.map((e) => e.trim()).toList();
    }
    return ColumnMapping(
      dateCol: _matchHeader(headers, _dateHeaders),
      descriptionCol: _matchHeader(headers, _descHeaders),
      debitCol: _matchHeader(headers, _debitHeaders),
      creditCol: _matchHeader(headers, _creditHeaders),
      amountCol: _matchHeader(headers, _amountHeaders),
      balanceCol: _matchHeader(headers, _balHeaders),
      referenceCol: _matchHeader(headers, _refHeaders),
    );
  }

  static DateTime? parseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    for (final fmt in [
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$'),
      RegExp(r'^(\d{2})/(\d{2})/(\d{4})$'),
      RegExp(r'^(\d{2})-(\d{2})-(\d{4})$'),
      RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$'),
    ]) {
      final m = fmt.firstMatch(s);
      if (m == null) continue;
      if (fmt.pattern.contains(r'(\d{4})-(\d{2})')) {
        final y = int.tryParse(m.group(1)!);
        final mo = int.tryParse(m.group(2)!);
        final d = int.tryParse(m.group(3)!);
        if (y != null && mo != null && d != null) return DateTime(y, mo, d);
      } else if (m.groupCount >= 3) {
        final a = int.tryParse(m.group(1)!);
        final b = int.tryParse(m.group(2)!);
        final y = int.tryParse(m.group(3)!);
        if (a != null && b != null && y != null) {
          if (a > 12) {
            return DateTime(y, b, a);
          }
          return DateTime(y, a, b);
        }
      }
    }
    return null;
  }

  static double? parseAmount(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    var neg = false;
    if (s.startsWith('(') && s.endsWith(')')) {
      neg = true;
      s = s.substring(1, s.length - 1);
    }
    s = s.replaceAll(',', '').replaceAll('₹', '').replaceAll(r'$', '').replaceAll('€', '').trim();
    if (s.endsWith(' DR') || s.endsWith(' dr')) {
      neg = true;
      s = s.substring(0, s.length - 3).trim();
    }
    if (s.endsWith(' CR') || s.endsWith(' cr')) {
      s = s.substring(0, s.length - 3).trim();
    }
    final v = double.tryParse(s);
    if (v == null) return null;
    return neg ? -v.abs() : v;
  }

  static StatementParseOutcome parseGrid(
    List<List<String>> grid, {
    ColumnMapping? mappingOverride,
    int headerRowIndex = 0,
  }) {
    final warnings = <String>[];
    if (grid.length < 2) {
      return StatementParseOutcome(rows: [], confidence: 0, mapping: const ColumnMapping(), warnings: ['Not enough rows']);
    }
    var map = mappingOverride ?? inferMapping(grid);
    if (!map.hasMinimum) {
      map = inferMapping(grid);
    }
    if (!map.hasMinimum) {
      return StatementParseOutcome(rows: [], confidence: 15, mapping: map, warnings: ['Could not infer date and amount columns']);
    }
    final dataStart = _headerRowIndex(grid, map) + 1;
    final rows = <ParsedStatementTxn>[];
    var ok = 0;
    var tried = 0;
    DateTime? minD;
    DateTime? maxD;
    for (var r = dataStart; r < grid.length; r++) {
      final line = grid[r];
      if (line.every((e) => e.trim().isEmpty)) continue;
      tried++;
      final ds = map.dateCol != null && map.dateCol! < line.length ? line[map.dateCol!] : '';
      final dt = parseDate(ds);
      if (dt == null) continue;
      final desc = map.descriptionCol != null && map.descriptionCol! < line.length ? line[map.descriptionCol!].trim() : '';
      double? amt;
      String direction = 'debit';
      if (map.amountCol != null && map.amountCol! < line.length) {
        final p = parseAmount(line[map.amountCol!]);
        if (p != null) {
          amt = p.abs();
          direction = p >= 0 ? 'debit' : 'credit';
        }
      } else {
        double? dr;
        double? cr;
        if (map.debitCol != null && map.debitCol! < line.length) {
          dr = parseAmount(line[map.debitCol!])?.abs();
        }
        if (map.creditCol != null && map.creditCol! < line.length) {
          cr = parseAmount(line[map.creditCol!])?.abs();
        }
        if ((dr ?? 0) > 0 && (cr ?? 0) > 0) {
          warnings.add('Row $r has both debit and credit; skipped.');
          continue;
        }
        if ((dr ?? 0) > 0) {
          amt = dr;
          direction = 'debit';
        } else if ((cr ?? 0) > 0) {
          amt = cr;
          direction = 'credit';
        }
      }
      if (amt == null || amt <= 0) continue;
      if (desc.toLowerCase().contains('opening balance') || desc.toLowerCase().contains('closing balance')) {
        continue;
      }
      ok++;
      if (minD == null || dt.isBefore(minD)) minD = dt;
      if (maxD == null || dt.isAfter(maxD)) maxD = dt;
      double? bal;
      if (map.balanceCol != null && map.balanceCol! < line.length) {
        bal = parseAmount(line[map.balanceCol!]);
      }
      final ref = map.referenceCol != null && map.referenceCol! < line.length ? line[map.referenceCol!].trim() : null;
      rows.add(
        ParsedStatementTxn(
          rowIndex: r,
          txnDate: dt,
          description: desc.isEmpty ? 'Transaction' : desc,
          amount: amt,
          direction: direction,
          balance: bal,
          reference: ref,
        ),
      );
    }
    final rate = tried == 0 ? 0.0 : ok / tried;
    var conf = (rate * 85 + (map.hasMinimum ? 15 : 0)).clamp(0.0, 100.0);
    if (rows.length < 3) {
      conf = conf * 0.6;
      warnings.add('Few transactions parsed — verify column mapping.');
    }
    return StatementParseOutcome(
      rows: rows,
      confidence: conf,
      mapping: map,
      periodStart: minD,
      periodEnd: maxD,
      warnings: warnings,
    );
  }

  static int _headerRowIndex(List<List<String>> grid, ColumnMapping map) {
    for (var r = 0; r < grid.length.clamp(0, 30); r++) {
      final row = grid[r].map((e) => e.trim().toLowerCase()).toList();
      final joined = row.join(' ');
      if (_dateHeaders.any(joined.contains)) return r;
    }
    return 0;
  }
}
