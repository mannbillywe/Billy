import 'dart:developer' as developer;

/// Centralized logging for Billy - visible in browser console (web) and debug console.
class BillyLogger {
  static const _tag = 'Billy';

  static void _log(String level, String message, [Object? error, StackTrace? stack]) {
    final timestamp = DateTime.now().toIso8601String();
    final full = '[$timestamp] [$level] $message';
    developer.log(full, name: _tag);
    if (error != null) {
      developer.log('Error: $error', name: _tag);
    }
    if (stack != null) {
      developer.log('Stack: $stack', name: _tag);
    }
    // Also print so it shows in browser console for web
    // ignore: avoid_print
    print('$_tag: $full');
    if (error != null) {
      // ignore: avoid_print
      print('$_tag: Error: $error');
    }
  }

  static void info(String message) => _log('INFO', message);

  static void warn(String message, [Object? error]) => _log('WARN', message, error);

  static void error(String message, [Object? error, StackTrace? stack]) =>
      _log('ERROR', message, error, stack);

  /// Log extraction failure - detects rate limit vs other causes.
  static void extractionFailed(Object err, StackTrace? stack) {
    final errStr = err.toString().toLowerCase();
    final isRateLimit = errStr.contains('429') ||
        errStr.contains('rate limit') ||
        errStr.contains('quota') ||
        errStr.contains('resource exhausted') ||
        errStr.contains('too many requests');

    if (isRateLimit) {
      error('EXTRACTION FAILED: API rate limit hit', err, stack);
      info('Rate limit detected - user should wait or use their own API key');
    } else {
      error('EXTRACTION FAILED', err, stack);
    }
  }
}
