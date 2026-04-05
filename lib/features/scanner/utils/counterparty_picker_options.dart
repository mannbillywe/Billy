/// Options for lend/borrow counterparty: accepted connections plus pending contact invites.
class CounterpartyPickerOption {
  const CounterpartyPickerOption({
    required this.key,
    required this.label,
    this.linkedUserId,
    this.suggestedName,
  });

  /// `u:<uuid>` or `e:<lowercase_email>`.
  final String key;
  final String label;
  final String? linkedUserId;
  final String? suggestedName;

  static List<CounterpartyPickerOption> build({
    required String myUserId,
    required List<Map<String, dynamic>> connections,
    required List<Map<String, dynamic>> invitations,
  }) {
    final byKey = <String, CounterpartyPickerOption>{};

    for (final c in connections) {
      final id = c['other_user_id'] as String?;
      if (id == null) continue;
      final name = (c['display_name'] as String?)?.trim().isNotEmpty == true
          ? c['display_name'] as String
          : 'Contact';
      byKey['u:$id'] = CounterpartyPickerOption(
        key: 'u:$id',
        label: name,
        linkedUserId: id,
        suggestedName: name,
      );
    }

    for (final inv in invitations) {
      if (inv['status'] != 'pending') continue;
      final from = inv['from_user_id'] as String?;
      final toEmail = (inv['to_email'] as String?)?.trim() ?? '';
      if (toEmail.isEmpty) continue;
      if (from != myUserId) continue;

      final toUid = inv['to_user_id'] as String?;
      if (toUid != null) {
        if (byKey.containsKey('u:$toUid')) continue;
        byKey['u:$toUid'] = CounterpartyPickerOption(
          key: 'u:$toUid',
          label: 'Invite: $toEmail',
          linkedUserId: toUid,
          suggestedName: toEmail.split('@').first,
        );
      } else {
        final k = 'e:${toEmail.toLowerCase()}';
        byKey[k] = CounterpartyPickerOption(
          key: k,
          label: 'Pending: $toEmail',
          linkedUserId: null,
          suggestedName: toEmail.split('@').first,
        );
      }
    }

    final list = byKey.values.toList()..sort((a, b) => a.label.compareTo(b.label));
    return list;
  }
}
