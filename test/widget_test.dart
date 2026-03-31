// Basic Flutter widget smoke test for Billy app.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:billy/app/app.dart';
import 'package:billy/config/supabase_config.dart';

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  });

  testWidgets('Billy app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: BillyApp(),
      ),
    );

    // App loads - either login screen or main shell
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
