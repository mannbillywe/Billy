import '../../../core/utils/document_date_range.dart';
import '../utils/goat_dashboard_helpers.dart';
import 'goat_analysis_lens.dart';

/// Source-aware dataset helpers for GOAT analytics (Smart, Statements, Receipts, Combined).
class GoatLensDatasets {
  GoatLensDatasets._();

  static Set<String> excludedDocumentIdsFromLinks(List<Map<String, dynamic>> links) {
    final out = <String>{};
    for (final l in links) {
      if (l['is_excluded_from_double_count'] == true) {
        final id = l['document_id'] as String?;
        if (id != null) out.add(id);
      }
    }
    return out;
  }

  /// Rolling debit spend from statement rows (posted `txn_date`), same window as [spendLastDaysByBasis].
  static double statementDebitsLastDays(List<Map<String, dynamic>> statementRows, int days) =>
      sumStatementDebitsLastDays(statementRows, days);

  /// Document-side spend for the same window (non-draft), by activity day.
  static double documentSpendLastDays(
    List<Map<String, dynamic>> documents,
    int days,
    WeekSpendBasis basis,
  ) =>
      spendLastDaysByBasis(documents, days, basis);

  /// Smart lens: exclude linked duplicate documents from the document sum, add all active statement debits.
  static double smartWeekDebitSpend({
    required List<Map<String, dynamic>> documents,
    required List<Map<String, dynamic>> statementTransactions,
    required List<Map<String, dynamic>> documentLinks,
    required WeekSpendBasis basis,
    int windowDays = 7,
  }) {
    final excluded = excludedDocumentIdsFromLinks(documentLinks);
    final docPart = spendLastDaysByBasisExcluding(documents, windowDays, basis, excluded);
    final stmtPart = sumStatementDebitsLastDays(statementTransactions, windowDays);
    return docPart + stmtPart;
  }

  /// Resolves week debit total for the selected GOAT analysis lens.
  static double weekDebitSpendForLens({
    required GoatAnalysisLens lens,
    required WeekSpendBasis basis,
    required List<Map<String, dynamic>> documents,
    required List<Map<String, dynamic>> statementTransactions,
    required List<Map<String, dynamic>> documentLinks,
    int windowDays = 7,
  }) {
    switch (lens) {
      case GoatAnalysisLens.ocrOnly:
        return spendLastDaysByBasis(documents, windowDays, basis);
      case GoatAnalysisLens.statementsOnly:
        return sumStatementDebitsLastDays(statementTransactions, windowDays);
      case GoatAnalysisLens.combinedRaw:
        return spendLastDaysByBasis(documents, windowDays, basis) +
            sumStatementDebitsLastDays(statementTransactions, windowDays);
      case GoatAnalysisLens.smart:
        return smartWeekDebitSpend(
          documents: documents,
          statementTransactions: statementTransactions,
          documentLinks: documentLinks,
          basis: basis,
          windowDays: windowDays,
        );
    }
  }
}
