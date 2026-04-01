/// View-model helpers for [lend_borrow_entries].
///
/// Rows are stored from the creator's perspective (`user_id` + `type`).
/// When the current user is `counterparty_user_id`, [effectiveTypeForViewer]
/// flips lent/borrowed so totals and tabs match "my" obligations.
String effectiveTypeForViewer(Map<String, dynamic> row, String? myUid) {
  if (myUid == null) return row['type'] as String? ?? 'lent';
  final creatorId = row['user_id'] as String?;
  final cpId = row['counterparty_user_id'] as String?;
  final stored = row['type'] as String? ?? 'lent';
  if (creatorId == myUid) return stored;
  if (cpId == myUid) return stored == 'lent' ? 'borrowed' : 'lent';
  return stored;
}

/// Display name of the *other* party (creator vs counterparty), using profile
/// embeds (`creator_profile`, `counterparty_profile`) from the lend/borrow query.
String otherPartyDisplayName(Map<String, dynamic> row, String? myUid) {
  if (myUid == null) return row['counterparty_name'] as String? ?? '';
  final creatorId = row['user_id'] as String?;
  if (creatorId == myUid) {
    final cp = row['counterparty_profile'] as Map<String, dynamic>?;
    final fromProfile = cp?['display_name'] as String?;
    if (fromProfile != null && fromProfile.trim().isNotEmpty) return fromProfile.trim();
    return (row['counterparty_name'] as String? ?? '').trim();
  }
  final cr = row['creator_profile'] as Map<String, dynamic>?;
  final name = cr?['display_name'] as String?;
  if (name != null && name.trim().isNotEmpty) return name.trim();
  return (row['counterparty_name'] as String? ?? 'Contact').trim();
}

String lendBorrowRoleLine(Map<String, dynamic> row, String? myUid) {
  final t = effectiveTypeForViewer(row, myUid);
  return t == 'lent' ? 'You lent' : 'You borrowed';
}
