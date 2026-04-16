import 'package:intl/intl.dart';

/// When [documents.date] (vendor invoice date) is before the calendar day of
/// [created_at], the expense was added recently but dated in the past.
class DocumentBackdateHint {
  const DocumentBackdateHint({
    required this.shortLabel,
    required this.bannerTitle,
    required this.bannerBody,
  });

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
      shortLabel: 'Dated $inv \u00b7 uploaded $saved',
      bannerTitle: 'Older bill uploaded recently',
      bannerBody:
          'This bill is dated $inv but you uploaded it $saved. '
          '"This week" and analytics can count it by either date.',
    );
  }
}
