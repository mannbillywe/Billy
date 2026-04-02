import 'package:fetch_client/fetch_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'config/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web: Fetch API with CORS mode for Supabase (Storage + Edge Functions) from Vercel.
  // Mobile/desktop: default IO client.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    httpClient: kIsWeb ? FetchClient(mode: RequestMode.cors) : null,
  );

  runApp(
    const ProviderScope(
      child: BillyApp(),
    ),
  );
}
