import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/suggestions_provider.dart';
import '../../../providers/recurring_suggestions_provider.dart';

class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = ['All', 'Categories', 'Recurring', 'Duplicates', 'Budget Alerts'];

  static const _tabTypeFilters = <String, List<String>>{
    'Categories': ['category', 'merchant_normalize'],
    'Recurring': ['recurring_detect'],
    'Duplicates': ['duplicate_warning'],
    'Budget Alerts': ['budget_warning', 'anomaly_alert'],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filterByTab(List<Map<String, dynamic>> all) {
    final label = _tabs[_tabController.index];
    final types = _tabTypeFilters[label];
    if (types == null) return all;
    return all.where((s) => types.contains(s['suggestion_type'])).toList();
  }

  Future<void> _onAccept(String id) async {
    await ref.read(suggestionsProvider.notifier).acceptSuggestion(id);
  }

  Future<void> _onDismiss(String id) async {
    await ref.read(suggestionsProvider.notifier).dismissSuggestion(id);
  }

  Future<void> _onSnooze(String id) async {
    await ref.read(suggestionsProvider.notifier).snoozeSuggestion(
          id,
          const Duration(hours: 24),
        );
  }

  @override
  Widget build(BuildContext context) {
    final suggestionsAsync = ref.watch(suggestionsProvider);
    ref.watch(recurringSuggestionsProvider);

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Suggestions',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: BillyTheme.gray800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Review smart recommendations for your finances',
                    style: TextStyle(fontSize: 14, color: BillyTheme.gray500),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              tabBar: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: BillyTheme.emerald700,
                unselectedLabelColor: BillyTheme.gray500,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                indicatorColor: BillyTheme.emerald600,
                indicatorWeight: 2.5,
                dividerHeight: 0.5,
                dividerColor: BillyTheme.gray200,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tabs: _tabs.map((t) => Tab(text: t)).toList(),
              ),
            ),
          ),
        ],
        body: suggestionsAsync.when(
          loading: () => const _LoadingState(),
          error: (err, _) => _ErrorState(
            message: err.toString(),
            onRetry: () => ref.invalidate(suggestionsProvider),
          ),
          data: (suggestions) {
            final filtered = _filterByTab(suggestions);
            if (filtered.isEmpty) return const _EmptyState();
            return RefreshIndicator(
              color: BillyTheme.emerald600,
              onRefresh: () async => ref.invalidate(suggestionsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final s = filtered[i];
                  return _SuggestionCard(
                    suggestion: s,
                    onAccept: () => _onAccept(s['id'] as String),
                    onDismiss: () => _onDismiss(s['id'] as String),
                    onSnooze: () => _onSnooze(s['id'] as String),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate({required this.tabBar});
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: BillyTheme.scaffoldBg,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}

class _SuggestionCard extends StatefulWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.onAccept,
    required this.onDismiss,
    required this.onSnooze,
  });

  final Map<String, dynamic> suggestion;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;
  final VoidCallback onSnooze;

  @override
  State<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<_SuggestionCard> {
  bool _acting = false;

  Future<void> _wrap(VoidCallback action) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      action();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;
    final type = s['suggestion_type'] as String? ?? '';
    final title = s['title'] as String? ?? _fallbackTitle(type);
    final description = s['description'] as String? ?? '';
    final confidence = s['confidence'] as String? ?? 'medium';

    final iconData = _iconForType(type);
    final iconBg = _iconBgForType(type);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(iconData, size: 20, color: _iconFgForType(type)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: BillyTheme.gray800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ConfidenceBadge(level: confidence),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 13,
                            color: BillyTheme.gray500,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: BillyTheme.gray100)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Accept',
                    icon: Icons.check_rounded,
                    color: BillyTheme.emerald600,
                    bgColor: BillyTheme.emerald50,
                    onTap: _acting ? null : () => _wrap(widget.onAccept),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    label: 'Dismiss',
                    icon: Icons.close_rounded,
                    color: BillyTheme.gray600,
                    bgColor: BillyTheme.gray100,
                    onTap: _acting ? null : () => _wrap(widget.onDismiss),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    label: 'Snooze',
                    icon: Icons.snooze_rounded,
                    color: const Color(0xFF3B82F6),
                    bgColor: const Color(0xFFEFF6FF),
                    onTap: _acting ? null : () => _wrap(widget.onSnooze),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'category':
        return Icons.label_outlined;
      case 'merchant_normalize':
        return Icons.store_outlined;
      case 'recurring_detect':
        return Icons.repeat_rounded;
      case 'duplicate_warning':
        return Icons.copy_rounded;
      case 'import_match':
        return Icons.compare_arrows_rounded;
      case 'settlement_suggest':
        return Icons.handshake_outlined;
      case 'split_suggest':
        return Icons.call_split_rounded;
      case 'anomaly_alert':
        return Icons.warning_amber_rounded;
      case 'ocr_correction':
        return Icons.spellcheck_rounded;
      case 'budget_warning':
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.lightbulb_outline_rounded;
    }
  }

  static Color _iconBgForType(String type) {
    switch (type) {
      case 'category':
      case 'merchant_normalize':
        return const Color(0xFFF0F9FF);
      case 'recurring_detect':
        return BillyTheme.emerald50;
      case 'duplicate_warning':
        return const Color(0xFFFFF7ED);
      case 'anomaly_alert':
      case 'budget_warning':
        return const Color(0xFFFEF2F2);
      case 'import_match':
      case 'settlement_suggest':
      case 'split_suggest':
        return const Color(0xFFF5F3FF);
      case 'ocr_correction':
        return const Color(0xFFFEFCE8);
      default:
        return BillyTheme.gray50;
    }
  }

  static Color _iconFgForType(String type) {
    switch (type) {
      case 'category':
      case 'merchant_normalize':
        return const Color(0xFF3B82F6);
      case 'recurring_detect':
        return BillyTheme.emerald600;
      case 'duplicate_warning':
        return const Color(0xFFF97316);
      case 'anomaly_alert':
      case 'budget_warning':
        return BillyTheme.red500;
      case 'import_match':
      case 'settlement_suggest':
      case 'split_suggest':
        return const Color(0xFF8B5CF6);
      case 'ocr_correction':
        return const Color(0xFFEAB308);
      default:
        return BillyTheme.gray600;
    }
  }

  static String _fallbackTitle(String type) {
    switch (type) {
      case 'category':
        return 'Category suggestion';
      case 'merchant_normalize':
        return 'Merchant cleanup';
      case 'recurring_detect':
        return 'Recurring detected';
      case 'duplicate_warning':
        return 'Possible duplicate';
      case 'import_match':
        return 'Import match';
      case 'settlement_suggest':
        return 'Settlement suggestion';
      case 'split_suggest':
        return 'Split suggestion';
      case 'anomaly_alert':
        return 'Spending anomaly';
      case 'ocr_correction':
        return 'OCR correction';
      case 'budget_warning':
        return 'Budget alert';
      default:
        return 'Suggestion';
    }
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.level});
  final String level;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (level) {
      'high' => (BillyTheme.emerald50, BillyTheme.emerald700),
      'low' => (const Color(0xFFFEF2F2), BillyTheme.red500),
      _ => (const Color(0xFFFFF7ED), const Color(0xFFF97316)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        level[0].toUpperCase() + level.substring(1),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: BillyTheme.emerald50,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.check_circle_rounded,
                size: 36,
                color: BillyTheme.emerald600,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "You're all caught up!",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: BillyTheme.gray800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No pending suggestions right now.\nWe\'ll notify you when something needs your attention.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: BillyTheme.gray500,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const _ShimmerCard(),
    );
  }
}

class _ShimmerCard extends StatefulWidget {
  const _ShimmerCard();

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final opacity = 0.04 + (_animation.value * 0.06);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BillyTheme.gray200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: BillyTheme.gray800.withValues(alpha: opacity),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 14,
                          width: 160,
                          decoration: BoxDecoration(
                            color: BillyTheme.gray800.withValues(alpha: opacity),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 12,
                          width: 220,
                          decoration: BoxDecoration(
                            color: BillyTheme.gray800.withValues(alpha: opacity),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: List.generate(
                  3,
                  (_) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Container(
                        height: 34,
                        decoration: BoxDecoration(
                          color: BillyTheme.gray800.withValues(alpha: opacity),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: BillyTheme.red500.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.error_outline_rounded,
                size: 36,
                color: BillyTheme.red500,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: BillyTheme.gray800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: BillyTheme.gray500,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
              style: FilledButton.styleFrom(
                backgroundColor: BillyTheme.emerald600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
