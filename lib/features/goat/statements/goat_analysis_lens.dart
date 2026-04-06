/// GOAT-wide analysis lens (deterministic dataset selection).
enum GoatAnalysisLens {
  smart,
  statementsOnly,
  ocrOnly,
  combinedRaw;

  String get dbValue => switch (this) {
        GoatAnalysisLens.smart => 'smart',
        GoatAnalysisLens.statementsOnly => 'statements_only',
        GoatAnalysisLens.ocrOnly => 'ocr_only',
        GoatAnalysisLens.combinedRaw => 'combined_raw',
      };

  String get label => switch (this) {
        GoatAnalysisLens.smart => 'Smart',
        GoatAnalysisLens.statementsOnly => 'Statements',
        GoatAnalysisLens.ocrOnly => 'Bills & receipts',
        GoatAnalysisLens.combinedRaw => 'Combined raw',
      };

  String get shortHint => switch (this) {
        GoatAnalysisLens.smart => 'Deduped: statement rows win when matched to a receipt.',
        GoatAnalysisLens.statementsOnly => 'Bank/card statement imports only.',
        GoatAnalysisLens.ocrOnly => 'Documents and manual ledger only.',
        GoatAnalysisLens.combinedRaw => 'All sources; may double-count.',
      };

  static GoatAnalysisLens fromDb(String? raw) {
    switch (raw) {
      case 'statements_only':
        return GoatAnalysisLens.statementsOnly;
      case 'ocr_only':
        return GoatAnalysisLens.ocrOnly;
      case 'combined_raw':
        return GoatAnalysisLens.combinedRaw;
      default:
        return GoatAnalysisLens.smart;
    }
  }
}
