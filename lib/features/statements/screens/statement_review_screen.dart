import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/transactions_provider.dart';
import '../../../services/transaction_service.dart';

class StatementReviewScreen extends ConsumerStatefulWidget {
  const StatementReviewScreen({
    super.key,
    required this.bankName,
    required this.rows,
    this.importId,
  });

  final String bankName;
  final List<Map<String, dynamic>> rows;
  final String? importId;

  @override
  ConsumerState<StatementReviewScreen> createState() =>
      _StatementReviewScreenState();
}

class _StatementReviewScreenState extends ConsumerState<StatementReviewScreen> {
  late Set<int> _selectedIndices;
  String _filterMode = 'all';
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _selectedIndices = Set<int>.from(
      List.generate(widget.rows.length, (i) => i),
    );
  }

  List<int> get _filteredIndices {
    switch (_filterMode) {
      case 'verified':
        return List.generate(widget.rows.length, (i) => i)
            .where((i) => widget.rows[i]['matched'] == true)
            .toList();
      case 'unmatched':
        return List.generate(widget.rows.length, (i) => i)
            .where((i) => widget.rows[i]['matched'] != true)
            .toList();
      default:
        return List.generate(widget.rows.length, (i) => i);
    }
  }

  int get _matchedCount =>
      widget.rows.where((r) => r['matched'] == true).length;

  double get _successRate =>
      widget.rows.isEmpty ? 0 : (_matchedCount / widget.rows.length) * 100;

  double get _selectedTotal {
    double total = 0;
    for (final i in _selectedIndices) {
      total += ((widget.rows[i]['amount'] as num?)?.toDouble() ?? 0).abs();
    }
    return total;
  }

  Future<void> _processRows() async {
    if (_selectedIndices.isEmpty) return;
    setState(() => _processing = true);
    try {
      int count = 0;
      for (final i in _selectedIndices) {
        final row = widget.rows[i];
        final id = await TransactionService.insertTransaction(
          title: row['vendor'] as String? ?? 'Unknown',
          amount: ((row['amount'] as num?)?.toDouble() ?? 0).abs(),
          date: row['date'] as String? ?? DateTime.now().toIso8601String().substring(0, 10),
          type: 'expense',
          sourceType: 'statement',
          sourceImportId: widget.importId,
          description: row['category'] as String?,
        );
        if (id != null) count++;
      }
      ref.read(transactionsProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count transactions imported'),
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
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: BillyTheme.red500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String?;
    final filtered = _filteredIndices;

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildStatsRow(),
                  const SizedBox(height: 24),
                  _buildSectionHeader(),
                  const SizedBox(height: 12),
                  ...filtered.map((i) => _buildTransactionRow(i, currency)),
                ],
              ),
            ),
            _buildBottomBar(currency),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: BillyTheme.gray100),
                ),
                child: const Icon(Icons.arrow_back_ios_new,
                    size: 16, color: BillyTheme.gray800),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: BillyTheme.emerald50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Success Rate: ${_successRate.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: BillyTheme.emerald700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'IMPORT SUMMARY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: BillyTheme.gray400,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Reviewing Statement',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: BillyTheme.gray800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We\'ve parsed your CSV export from ${widget.bankName}. '
          'Please verify the AI-suggested categories before processing.',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: BillyTheme.gray500,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStatCard(
          label: 'ROWS DETECTED',
          value: '${widget.rows.length}',
          isGradient: false,
        )),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard(
          label: 'SUGGESTED MATCHES',
          value: '$_matchedCount',
          isGradient: true,
        )),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required bool isGradient,
  }) {
    final bgDecoration = isGradient
        ? BoxDecoration(
            gradient: const LinearGradient(
              colors: [BillyTheme.emerald700, BillyTheme.emerald600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          )
        : BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: BillyTheme.gray100),
          );

    final textColor = isGradient ? Colors.white : BillyTheme.gray800;
    final labelColor =
        isGradient ? Colors.white.withValues(alpha: 0.8) : BillyTheme.gray400;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: bgDecoration,
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      children: [
        const Text(
          'Detected Transactions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: BillyTheme.gray800,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _showFilterMenu,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: BillyTheme.gray200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.filter_list_rounded,
                    size: 16, color: BillyTheme.gray600),
                const SizedBox(width: 4),
                Text(
                  'Filter Results',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: BillyTheme.gray600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showFilterMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filter Transactions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: BillyTheme.gray800,
                ),
              ),
              const SizedBox(height: 16),
              _filterOption('all', 'All Rows', Icons.list_rounded),
              _filterOption('verified', 'Verified Only', Icons.verified_rounded),
              _filterOption('unmatched', 'Unmatched Only', Icons.help_outline_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterOption(String mode, String label, IconData icon) {
    final isActive = _filterMode == mode;
    return ListTile(
      leading: Icon(icon,
          color: isActive ? BillyTheme.emerald600 : BillyTheme.gray400),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          color: isActive ? BillyTheme.emerald700 : BillyTheme.gray800,
        ),
      ),
      trailing: isActive
          ? const Icon(Icons.check_rounded, color: BillyTheme.emerald600)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () {
        setState(() => _filterMode = mode);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildTransactionRow(int index, String? currency) {
    final row = widget.rows[index];
    final isSelected = _selectedIndices.contains(index);
    final vendor = row['vendor'] as String? ?? 'Unknown';
    final date = row['date'] as String? ?? '';
    final amount = ((row['amount'] as num?)?.toDouble() ?? 0).abs();
    final category = row['category'] as String?;
    final confidence = (row['confidence'] as num?)?.toInt();
    final matched = row['matched'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedIndices.remove(index);
            } else {
              _selectedIndices.add(index);
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? BillyTheme.emerald400 : BillyTheme.gray100,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedIndices.add(index);
                      } else {
                        _selectedIndices.remove(index);
                      }
                    });
                  },
                  activeColor: BillyTheme.emerald600,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  side: const BorderSide(color: BillyTheme.gray300, width: 1.5),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            vendor,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: BillyTheme.gray800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (category != null) _categoryBadge(category),
                        if (category == null) _uncategorizedBadge(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          date,
                          style: const TextStyle(
                            fontSize: 12,
                            color: BillyTheme.gray400,
                          ),
                        ),
                        if (matched && confidence != null) ...[
                          const SizedBox(width: 8),
                          _matchBadge(confidence),
                        ],
                        if (matched && confidence == null) ...[
                          const SizedBox(width: 8),
                          _verifiedBadge(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppCurrency.format(amount, currency),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: BillyTheme.gray800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoryBadge(String category) {
    final color = _categoryColor(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        category,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _uncategorizedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: BillyTheme.red500.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'UNCATEGORIZED',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: BillyTheme.red500,
        ),
      ),
    );
  }

  Widget _matchBadge(int confidence) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: BillyTheme.emerald50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'AI MATCH $confidence%',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: BillyTheme.emerald700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _verifiedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: BillyTheme.emerald50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 10, color: BillyTheme.emerald600),
          SizedBox(width: 3),
          Text(
            'VERIFIED',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: BillyTheme.emerald700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(String? currency) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: BillyTheme.gray100)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TOTAL SELECTED  ${AppCurrency.format(_selectedTotal, currency)}  '
            'from ${_selectedIndices.length} rows',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: BillyTheme.gray500,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _processing
                      ? null
                      : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BillyTheme.gray600,
                    side: const BorderSide(color: BillyTheme.gray300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'DISCARD SELECTION',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: (_processing || _selectedIndices.isEmpty)
                      ? null
                      : _processRows,
                  style: FilledButton.styleFrom(
                    backgroundColor: BillyTheme.emerald600,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: BillyTheme.gray200,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _processing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'PROCESS ROWS',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _categoryColor(String category) {
    final key = category.toLowerCase();
    const map = <String, Color>{
      'food': Color(0xFFf59e0b),
      'dining': Color(0xFFf59e0b),
      'groceries': Color(0xFF10b981),
      'transport': Color(0xFF3b82f6),
      'travel': Color(0xFF3b82f6),
      'shopping': Color(0xFF8b5cf6),
      'entertainment': Color(0xFFec4899),
      'utilities': Color(0xFF6366f1),
      'bills': Color(0xFF6366f1),
      'health': Color(0xFFef4444),
      'medical': Color(0xFFef4444),
      'education': Color(0xFF14b8a6),
      'rent': Color(0xFF78716c),
      'salary': Color(0xFF22c55e),
      'subscription': Color(0xFFa855f7),
    };
    for (final entry in map.entries) {
      if (key.contains(entry.key)) return entry.value;
    }
    return BillyTheme.gray500;
  }
}
