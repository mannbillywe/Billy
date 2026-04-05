import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import '../../../core/formatting/app_currency.dart';
import '../models/export_document.dart';

/// Generates CSV for Billy export
class CsvGenerator {
  CsvGenerator();

  final _dateFormat = DateFormat('yyyy-MM-dd');

  String generate({
    required List<ExportDocument> documents,
    required DateTime startDate,
    required DateTime endDate,
    String? currencyCode,
  }) {
    final currencyFormat = AppCurrency.formatter(currencyCode);
    final rows = <List<dynamic>>[
      ['Vendor', 'Date', 'Category', 'Type', 'Amount'],
      ...documents.map((d) => [
            d.vendorName,
            _dateFormat.format(d.date),
            d.category,
            d.type,
            currencyFormat.format(d.amount),
          ]),
    ];

    return const ListToCsvConverter().convert(rows);
  }
}
