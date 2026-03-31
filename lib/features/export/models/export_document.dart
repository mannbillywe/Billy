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
