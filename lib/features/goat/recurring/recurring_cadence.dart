/// Deterministic calendar steps for recurring_series.frequency (no LLM).
DateTime addRecurringPeriod(DateTime from, String frequency, int intervalCount) {
  final n = intervalCount < 1 ? 1 : intervalCount;
  switch (frequency) {
    case 'weekly':
      return from.add(Duration(days: 7 * n));
    case 'biweekly':
      return from.add(Duration(days: 14 * n));
    case 'monthly':
      var y = from.year;
      var m = from.month + n;
      while (m > 12) {
        m -= 12;
        y += 1;
      }
      final lastDay = DateTime(y, m + 1, 0).day;
      final d = from.day > lastDay ? lastDay : from.day;
      return DateTime(y, m, d);
    case 'quarterly':
      return addRecurringPeriod(from, 'monthly', 3 * n);
    case 'yearly':
      return DateTime(from.year + n, from.month, from.day);
    case 'custom':
    default:
      return from.add(Duration(days: 30 * n));
  }
}
