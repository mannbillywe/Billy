/// Values for `documents.category_source` (Postgres check constraint).
abstract final class DocumentCategorySource {
  static const manual = 'manual';
  static const ai = 'ai';
  static const rule = 'rule';
  static const legacy = 'legacy';
}
