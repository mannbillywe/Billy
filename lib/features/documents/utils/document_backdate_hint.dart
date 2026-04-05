import 'package:intl/intl.dart';

/// When [documents.date] (vendor invoice date) is before the calendar day of
/// [created_at], the expense was added recently but dated in the past — show a hint
/// so users know why “This week” may follow the save date, not the printed bill date.
class DocumentBackdateHint {
  const DocumentBackdateHint({
    required this.shortLabel,
    required this.bannerTitle,
    required this.bannerBody,
  });

  /// One line for compact lists (e.g. Recent).
  final String shortLabel;

  final String bannerTitle;
  final String bannerBody;

  static DateTime? _dayOnly(dynamic raw) {
    if (raw == null) return null;
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return null;
    return DateTime(dt.year, dt.month, dt.day);
  }

  static String _savedPhrase(DateTime savedDay, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (savedDay == today) return 'today';
    final y = today.subtract(const Duration(days: 1));
    if (savedDay == y) return 'yesterday';
    return DateFormat('dd MMM yyyy').format(savedDay);
  }

  /// Returns null when no hint should be shown.
  static DocumentBackdateHint? fromDocumentRow(Map<String, dynamic> d, [DateTime? now]) {
    if ((d['status'] as String?) == 'draft') return null;
    final n = now ?? DateTime.now();
    final docDay = _dayOnly(d['date']);
    final createdDay = _dayOnly(d['created_at']);
    if (docDay == null || createdDay == null) return null;
    if (!docDay.isBefore(createdDay)) return null;

    final inv = DateFormat('dd MMM yyyy').format(docDay);
    final saved = _savedPhrase(createdDay, n);
    return DocumentBackdateHint(
      shortLabel: 'Older bill · added $saved',
      bannerTitle: 'Invoice date is in the past',
      bannerBody:
          'This record uses the vendor’s bill date ($inv). You saved it $saved. '
          '“This week” and analytics can count it on the day you added it when the bill date is older.',
    );
  }
}
