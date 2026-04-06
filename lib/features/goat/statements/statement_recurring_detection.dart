import 'dart:collection';

/// Deterministic recurring-like patterns from statement debits (same normalized description).
class StatementRecurringDetection {
  StatementRecurringDetection._();

  static String _norm(String raw) {
    var s = raw.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAll(RegExp(r'\d{2,}'), '#');
    if (s.length > 48) s = s.substring(0, 48);
    return s;
  }

  static List<StatementRecurringCandidate> fromTransactions(List<Map<String, dynamic>> rows, {int minHits = 3}) {
    final counts = HashMap<String, int>();
    final totals = HashMap<String, double>();
    for (final t in rows) {
      if ((t['direction'] as String?) != 'debit') continue;
      if ((t['status'] as String?) != 'active') continue;
      final desc = (t['description_raw'] as String?)?.trim() ?? '';
      if (desc.length < 3) continue;
      final k = _norm(desc);
      if (k.length < 3) continue;
      counts[k] = (counts[k] ?? 0) + 1;
      totals[k] = (totals[k] ?? 0) + ((t['amount'] as num?)?.toDouble() ?? 0);
    }
    final out = <StatementRecurringCandidate>[];
    for (final e in counts.entries) {
      if (e.value >= minHits) {
        out.add(StatementRecurringCandidate(label: e.key, hitCount: e.value, totalAmount: totals[e.key] ?? 0));
      }
    }
    out.sort((a, b) => b.hitCount.compareTo(a.hitCount));
    return out;
  }
}

class StatementRecurringCandidate {
  const StatementRecurringCandidate({
    required this.label,
    required this.hitCount,
    required this.totalAmount,
  });

  final String label;
  final int hitCount;
  final double totalAmount;
}
