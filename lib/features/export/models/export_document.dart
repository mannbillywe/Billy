/// Document item for export (PDF/CSV)
class ExportDocument {
  const ExportDocument({
    required this.vendorName,
    required this.amount,
    required this.date,
    required this.category,
    this.type = 'receipt',
  });

  final String vendorName;
  final double amount;
  final DateTime date;
  final String category;
  final String type;
}

/// Maps Supabase `documents` rows to export rows; omits drafts.
List<ExportDocument> documentsForExport(List<Map<String, dynamic>> docs) {
  return docs
      .where((d) => (d['status'] as String?) != 'draft')
      .map(
        (d) => ExportDocument(
          vendorName: d['vendor_name'] as String? ?? '',
          amount: (d['amount'] as num?)?.toDouble() ?? 0,
          date: DateTime.tryParse(d['date'] as String? ?? '') ?? DateTime.now(),
          category: (d['description'] as String?)?.split(',').first.trim() ?? 'Other',
          type: d['type'] as String? ?? 'receipt',
        ),
      )
      .toList();
}
