import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/disputes_provider.dart';

class DisputeScreen extends ConsumerStatefulWidget {
  const DisputeScreen({
    super.key,
    required this.entityType,
    required this.entityId,
    this.groupId,
    this.transactionId,
  });

  final String entityType;
  final String entityId;
  final String? groupId;
  final String? transactionId;

  @override
  ConsumerState<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends ConsumerState<DisputeScreen> {
  final _reasonCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the issue')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(disputesProvider(widget.groupId).notifier).openDispute(
            entityType: widget.entityType,
            entityId: widget.entityId,
            reason: reason,
            groupId: widget.groupId,
            transactionId: widget.transactionId,
            proposedAmount: double.tryParse(_amountCtrl.text.trim()),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Dispute opened'),
            backgroundColor: BillyTheme.emerald600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('Open dispute'),
        backgroundColor: BillyTheme.scaffoldBg,
        foregroundColor: BillyTheme.gray800,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BillyTheme.red500.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BillyTheme.red400.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_outlined, color: BillyTheme.red500, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This will flag the ${widget.entityType.replaceAll('_', ' ')} for review by all group members.',
                      style: TextStyle(fontSize: 13, color: BillyTheme.gray700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _reasonCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What\'s wrong?',
                hintText: 'Describe the issue — wrong amount, missing items, etc.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Proposed correct amount (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: BillyTheme.red500,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit dispute'),
            ),
          ],
        ),
      ),
    );
  }
}
