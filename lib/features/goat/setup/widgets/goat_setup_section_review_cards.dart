import 'package:flutter/material.dart';

import '../../../../core/theme/goat_theme.dart';
import '../goat_setup_models.dart';

/// Section shell: title + optional subtitle.
class GoatSetupDraftReviewCard extends StatelessWidget {
  const GoatSetupDraftReviewCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GoatTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GoatTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: GoatTokens.textPrimary, fontWeight: FontWeight.w800),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

Widget _originChip(Map<String, dynamic> row) {
  final o = rowOriginLabel(row);
  final c = rowConfidence(row);
  final Color bg = o == 'user_provided'
      ? Colors.teal.withValues(alpha: 0.15)
      : o == 'defaulted'
          ? Colors.orange.withValues(alpha: 0.12)
          : GoatTokens.gold.withValues(alpha: 0.12);
  final Color fg = o == 'user_provided'
      ? Colors.tealAccent.shade100
      : o == 'defaulted'
          ? Colors.orange.shade200
          : GoatTokens.gold;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(
          o.replaceAll('_', ' '),
          style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(width: 6),
      Text('${(c * 100).round()}%', style: TextStyle(color: GoatTokens.textMuted, fontSize: 10)),
    ],
  );
}

InputDecoration _dec(String label, Color hint) {
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: hint),
    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: GoatTokens.borderSubtle)),
    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: GoatTokens.gold)),
  );
}

class _AccountRow extends StatefulWidget {
  const _AccountRow({required this.row, required this.onChanged});

  final Map<String, dynamic> row;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  late TextEditingController _name;
  late TextEditingController _bal;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.row['name']?.toString() ?? '');
    _bal = TextEditingController(text: '${widget.row['current_balance'] ?? 0}');
  }

  @override
  void didUpdateWidget(covariant _AccountRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row['name'] != widget.row['name']) {
      _name.text = widget.row['name']?.toString() ?? '';
    }
    if (oldWidget.row['current_balance'] != widget.row['current_balance']) {
      _bal.text = '${widget.row['current_balance'] ?? 0}';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _bal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Switch.adaptive(
                value: rowAccepted(r),
                activeThumbColor: GoatTokens.gold,
                onChanged: (v) => widget.onChanged(Map<String, dynamic>.from(r)..['accepted'] = v),
              ),
              Expanded(child: _originChip(r)),
            ],
          ),
          TextField(
            controller: _name,
            style: const TextStyle(color: GoatTokens.textPrimary),
            decoration: _dec('Name', GoatTokens.textMuted),
            onChanged: (s) => widget.onChanged(Map<String, dynamic>.from(r)..['name'] = s),
          ),
          TextField(
            controller: _bal,
            style: const TextStyle(color: GoatTokens.textPrimary),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _dec('Current balance', GoatTokens.textMuted),
            onChanged: (s) => widget.onChanged(Map<String, dynamic>.from(r)..['current_balance'] = double.tryParse(s) ?? 0),
          ),
          if (rowWarningsLine(r) != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(rowWarningsLine(r)!, style: TextStyle(color: GoatTokens.textMuted, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

class GoatSetupAccountsReviewCard extends StatelessWidget {
  const GoatSetupAccountsReviewCard({super.key, required this.rows, required this.onChanged});

  final List<Map<String, dynamic>> rows;
  final void Function(int index, Map<String, dynamic> next) onChanged;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text('No accounts extracted.', style: TextStyle(color: GoatTokens.textMuted, fontSize: 13));
    }
    return Column(
      children: List.generate(rows.length, (i) {
        return _AccountRow(
          row: rows[i],
          onChanged: (next) => onChanged(i, next),
        );
      }),
    );
  }
}

class _IncomeRow extends StatefulWidget {
  const _IncomeRow({required this.row, required this.onChanged});

  final Map<String, dynamic> row;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_IncomeRow> createState() => _IncomeRowState();
}

class _IncomeRowState extends State<_IncomeRow> {
  late TextEditingController _title;
  late TextEditingController _amt;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.row['title']?.toString() ?? '');
    _amt = TextEditingController(text: '${widget.row['expected_amount'] ?? 0}');
  }

  @override
  void didUpdateWidget(covariant _IncomeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row['title'] != widget.row['title']) _title.text = widget.row['title']?.toString() ?? '';
    if (oldWidget.row['expected_amount'] != widget.row['expected_amount']) {
      _amt.text = '${widget.row['expected_amount'] ?? 0}';
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Switch.adaptive(
                value: rowAccepted(r),
                activeThumbColor: GoatTokens.gold,
                onChanged: (v) => widget.onChanged(Map<String, dynamic>.from(r)..['accepted'] = v),
              ),
              Expanded(child: _originChip(r)),
            ],
          ),
          TextField(
            controller: _title,
            style: const TextStyle(color: GoatTokens.textPrimary),
            decoration: _dec('Title', GoatTokens.textMuted),
            onChanged: (s) => widget.onChanged(Map<String, dynamic>.from(r)..['title'] = s),
          ),
          TextField(
            controller: _amt,
            style: const TextStyle(color: GoatTokens.textPrimary),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _dec('Expected amount', GoatTokens.textMuted),
            onChanged: (s) => widget.onChanged(Map<String, dynamic>.from(r)..['expected_amount'] = double.tryParse(s) ?? 0),
          ),
        ],
      ),
    );
  }
}

class GoatSetupIncomeReviewCard extends StatelessWidget {
  const GoatSetupIncomeReviewCard({super.key, required this.rows, required this.onChanged});

  final List<Map<String, dynamic>> rows;
  final void Function(int index, Map<String, dynamic> next) onChanged;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text('No income streams extracted.', style: TextStyle(color: GoatTokens.textMuted, fontSize: 13));
    }
    return Column(
      children: List.generate(rows.length, (i) {
        return _IncomeRow(
          row: rows[i],
          onChanged: (next) => onChanged(i, next),
        );
      }),
    );
  }
}

class _RecurringRow extends StatefulWidget {
  const _RecurringRow({required this.row, required this.onChanged});

  final Map<String, dynamic> row;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_RecurringRow> createState() => _RecurringRowState();
}

class _RecurringRowState extends State<_RecurringRow> {
  late TextEditingController _title;
  late TextEditingController _amt;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.row['title']?.toString() ?? '');
    _amt = TextEditingController(text: '${widget.row['expected_amount'] ?? 0}');
  }

  @override
  void didUpdateWidget(covariant _RecurringRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row['title'] != widget.row['title']) _title.text = widget.row['title']?.toString() ?? '';
    if (oldWidget.row['expected_amount'] != widget.row['expected_amount']) {
      _amt.text = '${widget.row['expected_amount'] ?? 0}';
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Switch.adaptive(
                value: rowAccepted(r),
                activeThumbColor: GoatTokens.gold,
                onChanged: (v) => widget.onChanged(Map<String, dynamic>.from(r)..['accepted'] = v),
              ),
              Expanded(child: _originChip(r)),
            ],
          ),
          TextField(
            controller: _title,
            style: const TextStyle(color: GoatTokens.textPrimary),
            decoration: _dec('Title', GoatTokens.textMuted),
            onChanged: (s) => widget.onChanged(Map<String, dynamic>.from(r)..['title'] = s),
          ),
          TextField(
            controller: _amt,
            style: const TextStyle(color: GoatTokens.textPrimary),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _dec('Amount', GoatTokens.textMuted),
            onChanged: (s) => widget.onChanged(Map<String, dynamic>.from(r)..['expected_amount'] = double.tryParse(s) ?? 0),
          ),
        ],
      ),
    );
  }
}

class GoatSetupRecurringReviewCard extends StatelessWidget {
  const GoatSetupRecurringReviewCard({super.key, required this.rows, required this.onChanged});

  final List<Map<String, dynamic>> rows;
  final void Function(int index, Map<String, dynamic> next) onChanged;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text('No recurring bills extracted.', style: TextStyle(color: GoatTokens.textMuted, fontSize: 13));
    }
    return Column(
      children: List.generate(rows.length, (i) {
        return _RecurringRow(row: rows[i], onChanged: (next) => onChanged(i, next));
      }),
    );
  }
}

class _PlannedRow extends StatefulWidget {
  const _PlannedRow({required this.row, required this.onChanged});

  final Map<String, dynamic> row;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_PlannedRow> createState() => _PlannedRowState();
}

class _PlannedRowState extends State<_PlannedRow> {
  late TextEditingController _title;
  late TextEditingController _date;
  late TextEditingController _amt;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.row['title']?.toString() ?? '');
    _date = TextEditingController(text: widget.row['event_date']?.toString() ?? '');
    _amt = TextEditingController(text: '${widget.row['amount'] ?? 0}');
  }

  @override
  void didUpdateWidget(covariant _PlannedRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row['title'] != widget.row['title']) _title.text = widget.row['title']?.toString() ?? '';
    if (oldWidget.row['event_date'] != widget.row['event_date']) _date.text = widget.row['event_date']?.toString() ?? '';
    if (oldWidget.row['amount'] != widget.row['amount']) _amt.text = '${widget.row['amount'] ?? 0}';
  }

  @override
  void dispose() {
    _title.dispose();
    _date.dispose();
    _amt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Switch.adaptive(
                value: rowAccepted(r),
                activeThumbColor: GoatTokens.gold,
                onChanged: (v) => widget.onChanged(Map<String, dynamic>.from(r)..['accepted'] = v),
              ),
              Expanded(child: _originChip(r)),
            ],
          ),
          TextField(
            controller: _title,
            style: const TextStyle(color: GoatTokens.textPrimary),
            decoration: _dec('Title', GoatTokens.textMuted),
            onChanged: (s) => widget.onChanged(Map<String, dynamic>.from(r)..['title'] = s),
          ),
          TextField(
            controller: _date,
            style: const TextStyle(color: GoatTokens.textPrimary),
            decoration: _dec('Date YYYY-MM-DD', GoatTokens.textMuted),
            onChanged: (s) => widget.onChanged(Map<String, dynamic>.from(r)..['event_date'] = s),
          ),
          TextField(
            controller: _amt,
            style: const TextStyle(color: GoatTokens.textPrimary),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _dec('Amount', GoatTokens.textMuted),
            onChanged: (s) => widget.onChanged(Map<String, dynamic>.from(r)..['amount'] = double.tryParse(s) ?? 0),
          ),
        ],
      ),
    );
  }
}

class GoatSetupPlannedEventsReviewCard extends StatelessWidget {
  const GoatSetupPlannedEventsReviewCard({super.key, required this.rows, required this.onChanged});

  final List<Map<String, dynamic>> rows;
  final void Function(int index, Map<String, dynamic> next) onChanged;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text('No one-off events extracted.', style: TextStyle(color: GoatTokens.textMuted, fontSize: 13));
    }
    return Column(
      children: List.generate(rows.length, (i) {
        return _PlannedRow(row: rows[i], onChanged: (next) => onChanged(i, next));
      }),
    );
  }
}

class _GoalRow extends StatefulWidget {
  const _GoalRow({required this.row, required this.onChanged});

  final Map<String, dynamic> row;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_GoalRow> createState() => _GoalRowState();
}

class _GoalRowState extends State<_GoalRow> {
  late TextEditingController _title;
  late TextEditingController _tgt;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.row['title']?.toString() ?? '');
    _tgt = TextEditingController(text: '${widget.row['target_amount'] ?? 0}');
  }

  @override
  void didUpdateWidget(covariant _GoalRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row['title'] != widget.row['title']) _title.text = widget.row['title']?.toString() ?? '';
    if (oldWidget.row['target_amount'] != widget.row['target_amount']) {
      _tgt.text = '${widget.row['target_amount'] ?? 0}';
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _tgt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Switch.adaptive(
                value: rowAccepted(r),
                activeThumbColor: GoatTokens.gold,
                onChanged: (v) => widget.onChanged(Map<String, dynamic>.from(r)..['accepted'] = v),
              ),
              Expanded(child: _originChip(r)),
            ],
          ),
          TextField(
            controller: _title,
            style: const TextStyle(color: GoatTokens.textPrimary),
            decoration: _dec('Title', GoatTokens.textMuted),
            onChanged: (s) => widget.onChanged(Map<String, dynamic>.from(r)..['title'] = s),
          ),
          TextField(
            controller: _tgt,
            style: const TextStyle(color: GoatTokens.textPrimary),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _dec('Target amount', GoatTokens.textMuted),
            onChanged: (s) => widget.onChanged(Map<String, dynamic>.from(r)..['target_amount'] = double.tryParse(s) ?? 0),
          ),
        ],
      ),
    );
  }
}

class GoatSetupGoalsReviewCard extends StatelessWidget {
  const GoatSetupGoalsReviewCard({super.key, required this.rows, required this.onChanged});

  final List<Map<String, dynamic>> rows;
  final void Function(int index, Map<String, dynamic> next) onChanged;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text('No goals extracted.', style: TextStyle(color: GoatTokens.textMuted, fontSize: 13));
    }
    return Column(
      children: List.generate(rows.length, (i) {
        return _GoalRow(row: rows[i], onChanged: (next) => onChanged(i, next));
      }),
    );
  }
}

class GoatSetupSourcePreferenceCard extends StatelessWidget {
  const GoatSetupSourcePreferenceCard({super.key, required this.pref, required this.onChanged});

  final Map<String, dynamic> pref;
  final void Function(Map<String, dynamic> next) onChanged;

  @override
  Widget build(BuildContext context) {
    final raw = pref['statement_preference'] as String?;
    final v = const {'statements_first', 'receipts_first', 'smart_mixed', 'unknown'}.contains(raw) ? raw! : 'unknown';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Switch.adaptive(
              value: sourcePreferenceAccepted(pref),
              activeThumbColor: GoatTokens.gold,
              onChanged: (x) => onChanged(Map<String, dynamic>.from(pref)..['accepted'] = x),
            ),
            Expanded(
              child: Text(
                'Save statement / receipt preference',
                style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: v,
          dropdownColor: GoatTokens.surfaceElevated,
          style: const TextStyle(color: GoatTokens.textPrimary),
          decoration: _dec('Preference', GoatTokens.textMuted),
          items: const [
            DropdownMenuItem(value: 'smart_mixed', child: Text('Smart mix')),
            DropdownMenuItem(value: 'statements_first', child: Text('Statements first')),
            DropdownMenuItem(value: 'receipts_first', child: Text('Receipts first')),
            DropdownMenuItem(value: 'unknown', child: Text('Unknown / decide later')),
          ],
          onChanged: (nv) {
            if (nv == null) return;
            onChanged(Map<String, dynamic>.from(pref)..['statement_preference'] = nv);
          },
        ),
      ],
    );
  }
}
