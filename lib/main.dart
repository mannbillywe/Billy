import 'package:fetch_client/fetch_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web: Fetch API with CORS mode for Supabase (Storage + Edge Functions) from Vercel.
  // Mobile/desktop: default IO client.
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
