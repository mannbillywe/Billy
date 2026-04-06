import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Reads the first worksheet of an .xlsx (OOXML) into string rows using [archive] + [xml].
/// Deterministic; no external Excel engine (avoids archive/xml version conflicts).
class StatementXlsxReader {
  StatementXlsxReader._();

  static ArchiveFile? _file(Archive ar, String name) {
    for (final f in ar.files) {
      if (f.name == name) return f;
    }
    return null;
  }

  static String _decode(ArchiveFile f) => String.fromCharCodes(f.content as List<int>);

  static List<String> _parseSharedStrings(String xml) {
    if (xml.isEmpty) return [];
    final doc = XmlDocument.parse(xml);
    final out = <String>[];
    for (final si in doc.findAllElements('si')) {
      final texts = si.findAllElements('t').map((e) => e.innerText).join();
      out.add(texts);
    }
    return out;
  }

  static int _colLettersToIndex(String letters) {
    var n = 0;
    for (final c in letters.codeUnits) {
      n = n * 26 + (c - 64);
    }
    return n - 1;
  }

  static ({int col, int row})? _parseCellRef(String ref) {
    final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(ref.trim().toUpperCase());
    if (m == null) return null;
    return (col: _colLettersToIndex(m.group(1)!), row: int.parse(m.group(2)!));
  }

  /// Returns grid[row][col] sparse expanded to rectangular max bounds.
  static List<List<String>> readFirstSheet(Uint8List bytes) {
    final ar = ZipDecoder().decodeBytes(bytes);
    final ssFile = _file(ar, 'xl/sharedStrings.xml');
    final ss = _parseSharedStrings(ssFile == null ? '' : _decode(ssFile));
    ArchiveFile? sheetFile = _file(ar, 'xl/worksheets/sheet1.xml');
    if (sheetFile == null) {
      for (final f in ar) {
        if (f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml')) {
          sheetFile = f;
          break;
        }
      }
    }
    if (sheetFile == null) return [];
    final doc = XmlDocument.parse(_decode(sheetFile));
    var maxRow = 0;
    var maxCol = 0;
    final cells = <String, String>{};
    for (final rowEl in doc.findAllElements('row')) {
      for (final c in rowEl.findAllElements('c')) {
        final r = c.getAttribute('r');
        if (r == null) continue;
        final pos = _parseCellRef(r);
        if (pos == null) continue;
        if (pos.row > maxRow) maxRow = pos.row;
        if (pos.col > maxCol) maxCol = pos.col;
        final t = c.getAttribute('t');
        final vList = c.findElements('v').toList();
        final v = vList.isEmpty ? '' : vList.first.innerText;
        String cell;
        if (t == 's') {
          final i = int.tryParse(v);
          cell = i != null && i >= 0 && i < ss.length ? ss[i] : '';
        } else {
          cell = v;
        }
        cells['${pos.row}:${pos.col}'] = cell;
      }
    }
    if (maxRow == 0 && maxCol == 0 && cells.isEmpty) return [];
    final grid = List.generate(maxRow + 1, (_) => List<String>.filled(maxCol + 1, ''));
    for (final e in cells.entries) {
      final p = e.key.split(':');
      final ri = int.parse(p[0]);
      final ci = int.parse(p[1]);
      if (ri < grid.length && ci < grid[ri].length) {
        grid[ri][ci] = e.value;
      }
    }
    return grid;
  }
}
