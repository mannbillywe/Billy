import 'package:flutter/material.dart';

import '../../core/theme/billy_theme.dart';

class GoatModePlaceholderScreen extends StatefulWidget {
  const GoatModePlaceholderScreen({super.key});

  @override
  State<GoatModePlaceholderScreen> createState() => _GoatModePlaceholderScreenState();
}

class _GoatModePlaceholderScreenState extends State<GoatModePlaceholderScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  static const _features = [
    (Icons.auto_awesome_rounded, 'AI Financial Coach', 'Personalized money advice powered by Gemini'),
    (Icons.trending_up_rounded, 'Smart Forecasting', 'Predict cash flow and upcoming expenses'),
    (Icons.category_rounded, 'Auto Categorization', 'AI sorts every transaction automatically'),
    (Icons.savings_rounded, 'Savings Goals', 'Set targets and track progress with nudges'),
    (Icons.receipt_long_rounded, 'Receipt Intelligence', 'Deep insights from your scanned documents'),
    (Icons.notifications_active_rounded, 'Smart Alerts', 'Get warned before you overspend'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: BillyTheme.gray100),
                ),
                child: const Icon(Icons.arrow_back_ios_new, size: 14, color: BillyTheme.gray800),
              ),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'IN DEVELOPMENT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero section
                  ScaleTransition(
                    scale: _pulse,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF059669), Color(0xFF10B981), Color(0xFF34D399)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF059669).withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(Icons.rocket_launch_rounded, size: 36, color: Colors.white),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'GOAT Mode',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your AI-powered financial superpower',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Status card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.construction_rounded, size: 22, color: Color(0xFFF59E0B)),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Currently in the making',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: BillyTheme.gray800,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Our team is building something incredible. GOAT Mode will transform how you manage money.',
                                    style: TextStyle(fontSize: 13, color: BillyTheme.gray500, height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: const LinearProgressIndicator(
                            value: 0.35,
                            backgroundColor: Color(0xFFFEF3C7),
                            valueColor: AlwaysStoppedAnimation(Color(0xFFF59E0B)),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '35% complete',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFD97706)),
                            ),
                            Text(
                              'Est. launch: Coming soon',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: BillyTheme.gray400),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Upcoming features
                  const Text(
                    'WHAT\'S COMING',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: BillyTheme.gray400,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final (icon, title, subtitle) = _features[index];
                  final colors = [
                    BillyTheme.emerald600,
                    BillyTheme.blue400,
                    const Color(0xFF8B5CF6),
                    const Color(0xFFF59E0B),
                    const Color(0xFFEC4899),
                    const Color(0xFF06B6D4),
                  ];
                  final bgColors = [
                    BillyTheme.emerald50,
                    const Color(0xFFEFF6FF),
                    const Color(0xFFF5F3FF),
                    const Color(0xFFFEF3C7),
                    const Color(0xFFFCE7F3),
                    const Color(0xFFECFEFF),
                  ];
                  final color = colors[index % colors.length];
                  final bg = bgColors[index % bgColors.length];

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: BillyTheme.gray100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon, size: 20, color: color),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: BillyTheme.gray800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(fontSize: 11, color: BillyTheme.gray500, height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
                childCount: _features.length,
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      BillyTheme.emerald600.withValues(alpha: 0.06),
                      Colors.white,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: BillyTheme.emerald100),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.notifications_none_rounded, size: 28, color: BillyTheme.emerald600),
                    const SizedBox(height: 12),
                    const Text(
                      'Want early access?',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Keep using Billy and you\'ll be first to know when GOAT Mode drops.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: BillyTheme.gray500, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: BillyTheme.emerald600,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text(
                          'Back to Billy',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}
