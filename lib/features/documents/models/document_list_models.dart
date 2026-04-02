// Filters and sort for the documents / history list.

enum DocumentSourceFilter {
  all,
  receipts,
  invoices,
  manual,
  ocr,
  needsReview,
  groupLinked,
  lendBorrowLinked,
}

enum DocumentSortMode {
  newest,
  oldest,
  highestAmount,
  lowestAmount,
}

extension DocumentSourceFilterLabel on DocumentSourceFilter {
  String get label => switch (this) {
        DocumentSourceFilter.all => 'All',
        DocumentSourceFilter.receipts => 'Receipts',
        DocumentSourceFilter.invoices => 'Invoices',
        DocumentSourceFilter.manual => 'Manual',
        DocumentSourceFilter.ocr => 'OCR',
        DocumentSourceFilter.needsReview => 'Needs review',
        DocumentSourceFilter.groupLinked => 'Group',
        DocumentSourceFilter.lendBorrowLinked => 'Lend/borrow',
      };
}

extension DocumentSortModeLabel on DocumentSortMode {
  String get label => switch (this) {
        DocumentSortMode.newest => 'Newest',
        DocumentSortMode.oldest => 'Oldest',
        DocumentSortMode.highestAmount => 'Highest amount',
        DocumentSortMode.lowestAmount => 'Lowest amount',
      };
}

bool documentIsOcr(Map<String, dynamic> doc) {
  final ed = doc['extracted_data'];
  if (ed is Map) {
    final id = ed['invoice_id'];
    if (id != null && id.toString().trim().isNotEmpty) return true;
  }
  return false;
}

bool documentIsGroupLinked(Map<String, dynamic> doc) {
  final ed = doc['extracted_data'];
  if (ed is! Map) return false;
  if (ed['intent_group_expense'] != true) return false;
  final gid = ed['group_id']?.toString().trim() ?? '';
  return gid.isNotEmpty;
}

bool documentIsLendBorrowLinked(Map<String, dynamic> doc) {
  final ed = doc['extracted_data'];
  if (ed is! Map) return false;
  return ed['intent_lend_borrow'] == true;
}

/// OCR-linked doc that should be double-checked (low model confidence or user flag).
bool documentNeedsReview(Map<String, dynamic> doc) {
  if (!documentIsOcr(doc)) return false;
  final ed = doc['extracted_data'];
  if (ed is! Map) return false;
  final c = (ed['extraction_confidence'] as String?)?.toLowerCase() ?? 'medium';
  if (c == 'low') return true;
  if (ed['user_flagged_mismatch'] == true) return true;
  return false;
}

int _compareDate(Map<String, dynamic> a, Map<String, dynamic> b) {
  final da = DateTime.tryParse(a['date'] as String? ?? '') ?? DateTime(1970);
  final db = DateTime.tryParse(b['date'] as String? ?? '') ?? DateTime(1970);
  return da.compareTo(db);
}

int _compareAmount(Map<String, dynamic> a, Map<String, dynamic> b) {
  final na = (a['amount'] as num?)?.toDouble() ?? 0;
  final nb = (b['amount'] as num?)?.toDouble() ?? 0;
  return na.compareTo(nb);
}

/// Applies search, source filter, and sort (returns a new list).
List<Map<String, dynamic>> filterAndSortDocuments(
  List<Map<String, dynamic>> docs, {
  required String searchQuery,
  required DocumentSourceFilter filter,
  required DocumentSortMode sort,
}) {
  Iterable<Map<String, dynamic>> it = docs;
  final q = searchQuery.trim().toLowerCase();
  if (q.isNotEmpty) {
    it = it.where((d) {
      final v = (d['vendor_name'] as String? ?? '').toLowerCase();
      return v.contains(q);
    });
  }
  switch (filter) {
    case DocumentSourceFilter.all:
      break;
    case DocumentSourceFilter.receipts:
      it = it.where((d) => (d['type'] as String? ?? '') == 'receipt');
      break;
    case DocumentSourceFilter.invoices:
      it = it.where((d) => (d['type'] as String? ?? '') == 'invoice');
      break;
    case DocumentSourceFilter.manual:
      it = it.where((d) => !documentIsOcr(d));
      break;
    case DocumentSourceFilter.ocr:
      it = it.where(documentIsOcr);
      break;
    case DocumentSourceFilter.needsReview:
      it = it.where(documentNeedsReview);
      break;
    case DocumentSourceFilter.groupLinked:
      it = it.where(documentIsGroupLinked);
      break;
    case DocumentSourceFilter.lendBorrowLinked:
      it = it.where(documentIsLendBorrowLinked);
      break;
  }
  final list = List<Map<String, dynamic>>.from(it);
  switch (sort) {
    case DocumentSortMode.newest:
      list.sort((a, b) => -_compareDate(a, b));
      break;
    case DocumentSortMode.oldest:
      list.sort(_compareDate);
      break;
    case DocumentSortMode.highestAmount:
      list.sort((a, b) => -_compareAmount(a, b));
      break;
    case DocumentSortMode.lowestAmount:
      list.sort(_compareAmount);
      break;
  }
  return list;
}
