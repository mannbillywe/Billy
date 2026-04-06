import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Lightweight GOAT Mode analytics (debug logs + Sentry breadcrumbs when Sentry is configured).
void logGoatEvent(String name, [Map<String, Object?>? data]) {
  final line = data == null || data.isEmpty ? name : '$name $data';
  debugPrint('[goat_telemetry] $line');
  try {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: name,
        category: 'goat',
        level: SentryLevel.info,
        data: data,
      ),
    );
  } catch (_) {}
}
