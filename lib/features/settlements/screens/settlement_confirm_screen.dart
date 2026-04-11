import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/profile_provider.dart';
import '../../../services/activity_logger.dart';
import '../../../services/transaction_service.dart';

class SettlementConfirmScreen extends ConsumerStatefulWidget {
  const SettlementConfirmScreen({
    super.key,
    required this.settlement,
    required this.groupName,
  });

  final Map<String, dynamic> settlement;
  final String groupName;

  @override
  ConsumerState<SettlementConfirmScreen> createState() =>
      _SettlementConfirmScreenState();
}

class _SettlementConfirmScreenState
    extends ConsumerState<SettlementConfirmScreen> {
  bool _processing = false;

  String get _settlementId => widget.settlement['id'] as String;
  double get _amount =>
      (widget.settlement['amount'] as num?)?.toDouble() ?? 0;
  String get _status =>
      widget.settlement['status'] as String? ?? 'pending';

  Future<void> _confirm() async {
    setState(() => _processing = true);
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;

      await client.from('group_settlements').update({
        'status': 'confirmed',
        'confirmed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _settlementId);

      final txnId = await TransactionService.insertTransaction(
        amount: _amount,
        date: DateTime.now().toIso8601String().substring(0, 10),
        type: 'settlement_in',
        title: 'Settlement from ${widget.groupName}',
        sourceType: 'settlement',
        settlementId: _settlementId,
        groupId: widget.settlement['group_id'] as String?,
        effectiveAmount: _amount,
      );

      await ActivityLogger.log(
        eventType: 'settlement_confirmed',
        summary: 'Confirmed settlement of ${_amount.toStringAsFixed(2)}',
        targetUserId: widget.settlement['payer_user_id'] as String?,
        groupId: widget.settlement['group_id'] as String?,
        transactionId: txnId,
        entityType: 'settlement',
        entityId: _settlementId,
        visibility: 'group',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settlement confirmed'),
            backgroundColor: BillyTheme.emerald600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: BillyTheme.red500),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _processing = true);
    try {
      final client = Supabase.instance.client;
      await client.from('group_settlements').update({
        'status': 'rejected',
      }).eq('id', _settlementId);

      await ActivityLogger.log(
        eventType: 'settlement_rejected',
        summary: 'Rejected settlement of ${_amount.toStringAsFixed(2)}',
        targetUserId: widget.settlement['payer_user_id'] as String?,
        groupId: widget.settlement['group_id'] as String?,
        entityType: 'settlement',
        entityId: _settlementId,
        visibility: 'group',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settlement rejected'),
            backgroundColor: BillyTheme.red500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: BillyTheme.red500),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;
    final payerName =
        (widget.settlement['payer_profile'] as Map?)?['display_name'] as String? ?? 'Someone';
    final payeeName =
        (widget.settlement['payee_profile'] as Map?)?['display_name'] as String? ?? 'You';
    final note = widget.settlement['note'] as String?;
    final isPending = _status == 'pending';

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('Settlement'),
        backgroundColor: BillyTheme.scaffoldBg,
        foregroundColor: BillyTheme.gray800,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Center(
              child: Text(
                AppCurrency.format(_amount, currency),
                style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _statusColor(_status).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _status.toUpperCase(),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _statusColor(_status)),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: BillyTheme.gray100),
              ),
              child: Column(
                children: [
                  _row('From', payerName),
                  _row('To', payeeName),
                  _row('Group', widget.groupName),
                  if (note != null && note.isNotEmpty) _row('Note', note),
                ],
              ),
            ),
            if (isPending) ...[
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _processing ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: BillyTheme.emerald600,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _processing
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Confirm settlement'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _processing ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BillyTheme.red500,
                    side: const BorderSide(color: BillyTheme.red400),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Reject settlement'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: BillyTheme.gray500)),
          ),
          Expanded(
            child: Text(value,
                style:
                    TextStyle(fontSize: 14, color: BillyTheme.gray800)),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return BillyTheme.emerald600;
      case 'rejected':
        return BillyTheme.red500;
      default:
        return BillyTheme.yellow400;
    }
  }
}
