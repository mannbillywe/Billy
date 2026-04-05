import 'package:fetch_client/fetch_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'config/supabase_config.dart';

/// Safari can fail cross-origin POSTs when [FetchClient] sets fetch `keepalive` (small bodies).
class _NoKeepaliveFetchClient extends http.BaseClient {
  _NoKeepaliveFetchClient() : _inner = FetchClient(mode: RequestMode.cors);

  final FetchClient _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.persistentConnection = false;
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}

const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Future<void> bootstrap() async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
      httpClient: kIsWeb ? _NoKeepaliveFetchClient() : null,
    );

    runApp(
      const ProviderScope(
        child: BillyApp(),
      ),
    );
  }

  if (_sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;
        options.tracesSampleRate = kDebugMode ? 1.0 : 0.2;
      },
      appRunner: bootstrap,
    );
  } else {
    await bootstrap();
  }
}
