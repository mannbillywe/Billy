import 'package:intl/intl.dart';

/// Formats money using the user's preferred ISO 4217 code from profile.
class AppCurrency {
  AppCurrency._();

  static NumberFormat formatter(String? iso4217) {
    final code = (iso4217 == null || iso4217.trim().isEmpty) ? 'USD' : iso4217.trim().toUpperCase();
    try {
      return NumberFormat.simpleCurrency(name: code);
    } catch (_) {
      return NumberFormat.currency(symbol: r'$', decimalDigits: 2);
    }
  }

  static String format(double amount, String? iso4217) => formatter(iso4217).format(amount);
}
