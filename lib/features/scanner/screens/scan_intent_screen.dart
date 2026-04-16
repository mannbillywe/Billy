import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/transactions_provider.dart';

enum _IntentType { personal, shared, lend, borrow }

class ScanIntentScreen extends ConsumerStatefulWidget {
  const ScanIntentScreen({
    super.key,
    required this.vendor,
    required this.amount,
    required this.date,
    this.currency,
    this.documentId,
    this.extractedData,
  });

  final String vendor;
  final double amount;
  final String date;
  final String? currency;
  final String? documentId;
  final Map<String, dynamic>? extractedData;

  @override
  ConsumerState<ScanIntentScreen> createState() => _ScanIntentScreenState();
}

class _ScanIntentScreenState extends ConsumerState<ScanIntentScreen> {
  _IntentType _selected = _IntentType.personal;
  bool _saving = false;

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final String type;
      switch (_selected) {
        case _IntentType.personal:
        case _IntentType.shared:
          type = 'expense';
        case _IntentType.lend:
          type = 'lend';
        case _IntentType.borrow:
          type = 'borrow';
      }

      await ref.read(transactionsProvider.notifier).addTransaction(
            amount: widget.amount,
            date: widget.date,
            type: type,
            title: widget.vendor.isNotEmpty ? widget.vendor : 'Expense',
            sourceType: 'scan',
            currency: widget.currency,
            sourceDocumentId: widget.documentId,
            extractedData: widget.extractedData,
          );

      if (!mounted) return;

      if (_selected == _IntentType.shared) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Split flow coming soon'),
            backgroundColor: BillyTheme.emerald600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: BillyTheme.red500,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: BillyTheme.gray800),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Review Scan',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: BillyTheme.gray800,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: BillyTheme.emerald50,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: BillyTheme.emerald600,
              size: 22,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildVendorCard(),
                    const SizedBox(height: 28),
                    _buildIntentSection(),
                    const SizedBox(height: 24),
                    _buildAiSuggestionBar(),
                  ],
                ),
              ),
            ),
            _buildBottomActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildVendorCard() {
    final formattedAmount = AppCurrency.format(widget.amount, widget.currency);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.emerald100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DETECTED VENDOR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: BillyTheme.emerald600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.vendor.isNotEmpty ? widget.vendor : 'Unknown Vendor',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: BillyTheme.gray800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BillyTheme.emerald100.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: BillyTheme.emerald600,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TRANSACTION DATE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                        color: BillyTheme.gray500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.date,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: BillyTheme.gray800,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'TOTAL AMOUNT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                      color: BillyTheme.gray500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formattedAmount,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: BillyTheme.emerald600,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              // TODO: navigate to edit details screen
            },
            child: Text(
              'Edit details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BillyTheme.emerald600,
                decoration: TextDecoration.underline,
                decorationColor: BillyTheme.emerald600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Who is this for?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: BillyTheme.gray800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Assign this expense to a budget category',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: BillyTheme.gray500,
          ),
        ),
        const SizedBox(height: 18),
        _IntentOptionCard(
          icon: Icons.person_rounded,
          iconBg: const Color(0xFFDBEAFE),
          iconColor: const Color(0xFF3B82F6),
          title: 'Personal',
          subtitle: 'Private expense just for you',
          selected: _selected == _IntentType.personal,
          onTap: () => setState(() => _selected = _IntentType.personal),
        ),
        const SizedBox(height: 10),
        _IntentOptionCard(
          icon: Icons.group_rounded,
          iconBg: const Color(0xFFD1FAE5),
          iconColor: BillyTheme.emerald600,
          title: 'Shared (Split)',
          subtitle: 'Divide with your Greenhouse group',
          selected: _selected == _IntentType.shared,
          onTap: () => setState(() => _selected = _IntentType.shared),
        ),
        const SizedBox(height: 10),
        _IntentOptionCard(
          icon: Icons.send_rounded,
          iconBg: const Color(0xFFFED7AA),
          iconColor: const Color(0xFFF97316),
          title: 'Lend to Someone',
          subtitle: 'Expecting repayment later',
          selected: _selected == _IntentType.lend,
          onTap: () => setState(() => _selected = _IntentType.lend),
        ),
        const SizedBox(height: 10),
        _IntentOptionCard(
          icon: Icons.call_received_rounded,
          iconBg: const Color(0xFFE9D5FF),
          iconColor: const Color(0xFF8B5CF6),
          title: 'Borrow from Someone',
          subtitle: 'Paying back a previous debt',
          selected: _selected == _IntentType.borrow,
          onTap: () => setState(() => _selected = _IntentType.borrow),
        ),
      ],
    );
  }

  Widget _buildAiSuggestionBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: BillyTheme.emerald50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: BillyTheme.emerald600),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13, color: BillyTheme.gray700, height: 1.4),
                children: const [
                  TextSpan(text: "I've categorized this as "),
                  TextSpan(
                    text: 'Lifestyle & Home',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' based on your history.'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              // TODO: category change flow
            },
            child: Text(
              'CHANGE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: BillyTheme.emerald600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _saving ? null : _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: BillyTheme.emerald600,
                disabledBackgroundColor: BillyTheme.emerald400,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Confirm Transaction',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 20, color: Colors.white),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(
              'DISCARD SCAN',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: BillyTheme.gray500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntentOptionCard extends StatelessWidget {
  const _IntentOptionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? BillyTheme.emerald500 : BillyTheme.gray100;
    final bgColor = selected ? const Color(0xFFFAFFFE) : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: BillyTheme.emerald500.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: BillyTheme.gray800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: BillyTheme.gray500,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: BillyTheme.emerald600,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 16, color: Colors.white),
              )
            else
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: BillyTheme.gray300, width: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
