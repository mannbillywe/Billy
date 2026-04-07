import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/goat/statements/goat_analysis_lens.dart';
import '../features/goat/statements/statement_repository.dart';
import '../features/goat/utils/goat_dashboard_helpers.dart';
import 'documents_provider.dart';
import 'goat_lens_provider.dart';
import 'week_spend_basis_provider.dart';

/// Loaded once for the statement transaction detail screen.
class StatementTransactionDetailBundle {
  const StatementTransactionDetailBundle({
    required this.txn,
    required this.links,
    required this.categories,
  });

  final Map<String, dynamic> txn;
  final List<Map<String, dynamic>> links;
  final List<Map<String, dynamic>> categories;
}

Future<List<Map<String, dynamic>>> _safeStatements(Future<List<Map<String, dynamic>>> Function() fn) async {
  try {
    return await fn();
  } catch (_) {
    return [];
  }
}

final statementImportsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return _safeStatements(() => StatementRepository.fetchImports());
});

final statementTransactionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return _safeStatements(() => StatementRepository.fetchTransactions(limit: 500));
});

final statementAccountsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return _safeStatements(() => StatementRepository.fetchAccounts());
});

final statementDocumentLinksProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return _safeStatements(() => StatementRepository.fetchDocumentLinks(limit: 300));
});

final canonicalFinancialEventsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return _safeStatements(() => StatementRepository.fetchCanonicalEvents(limit: 800));
});

final statementImportReviewsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return _safeStatements(() => StatementRepository.fetchImportReviews(limit: 200));
});

final statementTransactionDetailProvider =
    FutureProvider.autoDispose.family<StatementTransactionDetailBundle?, String>((ref, id) async {
  final txn = await StatementRepository.fetchTransactionById(id);
  if (txn == null) return null;
  final links = await StatementRepository.fetchLinksForStatementTransaction(id);
  final categories = await StatementRepository.fetchCategoriesForPicker();
  return StatementTransactionDetailBundle(txn: txn, links: links, categories: categories);
});

/// 7-day debit spend for GOAT home: [goatAnalysisLensProvider] + same window/basis as home “7-day spend” for receipts.
final goatLensWeekDebitSpendProvider = FutureProvider<double>((ref) async {
  try {
    final lens = ref.watch(goatAnalysisLensProvider);
    final basis = ref.watch(weekSpendBasisProvider);
    const windowDays = 7;

    Future<double> docDebitByBasis() async {
      final docs = await ref.watch(documentsProvider.future);
      return spendLastDaysByBasis(docs, windowDays, basis);
    }

    Future<double> stmtDebitSum() async {
      final rows = await ref.watch(statementTransactionsProvider.future);
      return sumStatementDebitsLastDays(rows, windowDays);
    }

    switch (lens) {
      case GoatAnalysisLens.ocrOnly:
        return docDebitByBasis();
      case GoatAnalysisLens.statementsOnly:
        return stmtDebitSum();
      case GoatAnalysisLens.combinedRaw:
        return (await docDebitByBasis()) + (await stmtDebitSum());
      case GoatAnalysisLens.smart:
        final docs = await ref.watch(documentsProvider.future);
        final stmts = await ref.watch(statementTransactionsProvider.future);
        final links = await ref.watch(statementDocumentLinksProvider.future);
        final excludedDocs = <String>{};
        for (final l in links) {
          if (l['is_excluded_from_double_count'] == true) {
            final id = l['document_id'] as String?;
            if (id != null) excludedDocs.add(id);
          }
        }
        final docPart = spendLastDaysByBasisExcluding(docs, windowDays, basis, excludedDocs);
        final stmtPart = sumStatementDebitsLastDays(stmts, windowDays);
        return docPart + stmtPart;
    }
  } catch (_) {
    final docs = await ref.watch(documentsProvider.future);
    final basis = ref.read(weekSpendBasisProvider);
    return spendLastDaysByBasis(docs, 7, basis);
  }
});
