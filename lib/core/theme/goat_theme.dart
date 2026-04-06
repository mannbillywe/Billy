import 'package:flutter/material.dart';

/// Visual tokens for GOAT Mode only (reference: zip (2) React mock — zinc-950 + gold, no emerald shell).
abstract final class GoatTokens {
  static const Color background = Color(0xFF09090B);
  static const Color surface = Color(0xFF18181B);
  static const Color surfaceElevated = Color(0xFF27272A);
  static const Color borderSubtle = Color(0xFF3F3F46);
  static const Color textPrimary = Color(0xFFF4F4F5);
  static const Color textMuted = Color(0xFFA1A1AA);
  static const Color gold = Color(0xFFFACC15);
  static const Color goldDeep = Color(0xFFEAB308);
  static const Color goldMuted = Color(0xFFCA8A04);

  static List<BoxShadow> cardGlow = [
    BoxShadow(
      color: gold.withValues(alpha: 0.06),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}

abstract final class GoatTheme {
  static ThemeData darkTheme(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: GoatTokens.background,
      colorScheme: ColorScheme.dark(
        surface: GoatTokens.surface,
        primary: GoatTokens.gold,
        onPrimary: GoatTokens.background,
        secondary: GoatTokens.goldDeep,
        onSurface: GoatTokens.textPrimary,
        outline: GoatTokens.borderSubtle,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: GoatTokens.textPrimary,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: GoatTokens.surface,
        indicatorColor: GoatTokens.gold.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? GoatTokens.gold : GoatTokens.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? GoatTokens.gold : GoatTokens.textMuted, size: 22);
        }),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: GoatTokens.textPrimary,
        displayColor: GoatTokens.textPrimary,
      ),
    );
  }
}
