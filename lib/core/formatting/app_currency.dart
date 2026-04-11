import 'package:intl/intl.dart';

/// Formats money using the user's preferred ISO 4217 code from profile.
class AppCurrency {
  AppCurrency._();

  static final RegExp _iso4217 = RegExp(r'^[A-Z]{3}$');

  /// Normalizes profile currency: invalid or non–3-letter codes fall back to USD so intl does not emit odd prefixes.
  static String normalizedCurrencyCode(String? iso4217) {
    final raw = iso4217?.trim().toUpperCase() ?? '';
    if (raw.isEmpty || !_iso4217.hasMatch(raw)) return 'USD';
    return raw;
  }

  static NumberFormat formatter(String? iso4217) {
    final code = normalizedCurrencyCode(iso4217);
    try {
      return NumberFormat.simpleCurrency(name: code);
    } catch (_) {
      return NumberFormat.currency(symbol: r'$', decimalDigits: 2);
    }
  }

  static String format(double amount, String? iso4217) => formatter(iso4217).format(amount);

  /// Short label for profile-style stats (e.g. `₹1.2k` when over 1000).
  static String formatCompact(double amount, String? iso4217) {
    final f = formatter(iso4217);
    if (amount >= 1000) {
      return '${f.currencySymbol}${(amount / 1000).toStringAsFixed(1)}k';
    }
    return f.format(amount);
  }
}
