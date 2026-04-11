import '../features/scanner/models/extracted_receipt.dart';

class TransactionDraft {
  final String type; // expense, lend, borrow
  final double amount;
  final double effectiveAmount;
  final String title;
  final String? description;
  final String sourceType;
  final String? groupId;
  final String? counterpartyName;
  final String? counterpartyUserId;
  final String? lendType; // lent or borrowed
  final List<Map<String, dynamic>>? groupShares;
  final List<int> lineItemIndices;

  const TransactionDraft({
    required this.type,
    required this.amount,
    required this.effectiveAmount,
    required this.title,
    this.description,
    required this.sourceType,
    this.groupId,
    this.counterpartyName,
    this.counterpartyUserId,
    this.lendType,
    this.groupShares,
    this.lineItemIndices = const [],
  });
}

class LendBucket {
  final String name;
  final String? linkedUserId;
  double amount;
  final List<String> labels;

  LendBucket(this.name, this.linkedUserId)
      : amount = 0,
        labels = [];
}

enum MoneyIntent { personal, group, lend, borrow, mixed }

class AllocationResult {
  final List<TransactionDraft> transactions;
  final double totalEffectiveSpend;

  const AllocationResult({
    required this.transactions,
    required this.totalEffectiveSpend,
  });
}

class AllocationService {
  static double round2(double x) => (x * 100).round() / 100;

  static List<Map<String, dynamic>> computeGroupShares({
    required Map<String, double> aggregatedByUser,
    required double targetTotal,
  }) {
    final entries = aggregatedByUser.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) return [];
    var allocated = 0.0;
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < entries.length; i++) {
      final uid = entries[i].key;
      if (i == entries.length - 1) {
        out.add({'user_id': uid, 'share_amount': round2(targetTotal - allocated)});
      } else {
        final v = round2(entries[i].value);
        out.add({'user_id': uid, 'share_amount': v});
        allocated += v;
      }
    }
    return out;
  }

  static double computeEffectiveAmount({
    required double totalAmount,
    required List<Map<String, dynamic>> shares,
    required String currentUserId,
  }) {
    for (final s in shares) {
      if (s['user_id'] == currentUserId) {
        return (s['share_amount'] as num?)?.toDouble() ?? totalAmount;
      }
    }
    return totalAmount;
  }

  static List<LendBucket> computeLendBuckets({
    required List<LineItem> items,
    required List<bool> lineOn,
    required List<String> lineCounterpartyNames,
    required List<String?> lineLinkedUserIds,
    required String defaultCounterparty,
  }) {
    final buckets = <String, LendBucket>{};
    for (var i = 0; i < items.length; i++) {
      if (i >= lineOn.length || !lineOn[i]) continue;
      final perLine = i < lineCounterpartyNames.length ? lineCounterpartyNames[i].trim() : '';
      final name = perLine.isNotEmpty ? perLine : defaultCounterparty;
      final link = i < lineLinkedUserIds.length ? lineLinkedUserIds[i] : null;
      final key = '$name\u0001${link ?? ''}';
      final b = buckets.putIfAbsent(key, () => LendBucket(name, link));
      b.amount += items[i].total;
      final d = items[i].description.trim();
      if (d.isNotEmpty) b.labels.add(d);
    }
    return buckets.values.toList();
  }

  static AllocationResult computePersonalExpense({
    required ExtractedReceipt receipt,
    required List<bool> lineOn,
    required double allocationTotal,
    required String title,
  }) {
    final txn = TransactionDraft(
      type: 'expense',
      amount: allocationTotal,
      effectiveAmount: allocationTotal,
      title: title,
      sourceType: 'scan',
      lineItemIndices: [for (var i = 0; i < lineOn.length; i++) if (lineOn[i]) i],
    );
    return AllocationResult(
      transactions: [txn],
      totalEffectiveSpend: allocationTotal,
    );
  }

  static AllocationResult computeGroupExpense({
    required ExtractedReceipt receipt,
    required List<bool> lineOn,
    required double allocationTotal,
    required String title,
    required String groupId,
    required String currentUserId,
    required Map<String, double> sharesByUser,
  }) {
    final shares = computeGroupShares(
      aggregatedByUser: sharesByUser,
      targetTotal: allocationTotal,
    );
    final effective = computeEffectiveAmount(
      totalAmount: allocationTotal,
      shares: shares,
      currentUserId: currentUserId,
    );
    final txn = TransactionDraft(
      type: 'expense',
      amount: allocationTotal,
      effectiveAmount: effective,
      title: title,
      sourceType: 'scan',
      groupId: groupId,
      groupShares: shares,
      lineItemIndices: [for (var i = 0; i < lineOn.length; i++) if (lineOn[i]) i],
    );
    return AllocationResult(
      transactions: [txn],
      totalEffectiveSpend: effective,
    );
  }

  static AllocationResult computeLendExpense({
    required double allocationTotal,
    required String title,
    required String lendType,
    required String counterpartyName,
    String? counterpartyUserId,
  }) {
    final type = lendType == 'lent' ? 'lend' : 'borrow';
    final effective = lendType == 'lent' ? 0.0 : allocationTotal;
    final txn = TransactionDraft(
      type: type,
      amount: allocationTotal,
      effectiveAmount: effective,
      title: title,
      sourceType: 'scan',
      counterpartyName: counterpartyName,
      counterpartyUserId: counterpartyUserId,
      lendType: lendType,
    );
    return AllocationResult(
      transactions: [txn],
      totalEffectiveSpend: effective,
    );
  }
}
