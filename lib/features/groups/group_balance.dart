// Net balance per user: positive = the group owes them, negative = they owe the group.

Map<String, double> expenseNetFromRows(List<Map<String, dynamic>> expenses) {
  final net = <String, double>{};
  void add(String uid, double delta) {
    net[uid] = (net[uid] ?? 0) + delta;
  }

  for (final e in expenses) {
    final amount = (e['amount'] as num?)?.toDouble() ?? 0;
    final payer = e['paid_by_user_id'] as String?;
    if (payer != null && amount > 0) add(payer, amount);

    final parts = (e['group_expense_participants'] as List?) ?? [];
    for (final p in parts) {
      final m = p as Map<String, dynamic>;
      final uid = m['user_id'] as String?;
      final share = (m['share_amount'] as num?)?.toDouble() ?? 0;
      if (uid != null && share > 0) add(uid, -share);
    }
  }
  return net;
}

/// Apply settlements: payer sent money to payee, so payer's net decreases, payee's increases.
Map<String, double> applySettlements(
  Map<String, double> net,
  List<Map<String, dynamic>> settlements,
) {
  final out = Map<String, double>.from(net);
  void add(String uid, double delta) {
    out[uid] = (out[uid] ?? 0) + delta;
  }

  for (final s in settlements) {
    final payer = s['payer_user_id'] as String?;
    final payee = s['payee_user_id'] as String?;
    final amt = (s['amount'] as num?)?.toDouble() ?? 0;
    if (payer == null || payee == null || amt <= 0) continue;
    add(payer, -amt);
    add(payee, amt);
  }
  return out;
}

/// Ensure every [memberIds] appears in the map (0.0 if missing).
Map<String, double> netForMembers(Map<String, double> net, Iterable<String> memberIds) {
  final out = <String, double>{};
  for (final id in memberIds) {
    out[id] = net[id] ?? 0;
  }
  return out;
}
