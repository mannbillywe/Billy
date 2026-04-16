import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/billy_theme.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/screens/login_screen.dart';
import 'layout_shell.dart';

final _navKey = GlobalKey<NavigatorState>();

class BillyApp extends ConsumerWidget {
  const BillyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);

    ref.listen<AsyncValue<dynamic>>(authStateProvider, (prev, next) {
      final wasLoggedIn = prev?.valueOrNull != null;
      final isLoggedIn = next.valueOrNull != null;

      if (wasLoggedIn && !isLoggedIn) {
        _navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      } else if (!wasLoggedIn && isLoggedIn) {
        _navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const LayoutShell()),
          (_) => false,
        );
      }
    });

    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Billy',
      debugShowCheckedModeBanner: false,
      theme: BillyTheme.lightTheme,
      home: authAsync.when(
        data: (user) => user != null ? const LayoutShell() : const LoginScreen(),
        loading: () => const Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: CircularProgressIndicator(color: BillyTheme.emerald600),
          ),
        ),
        error: (e, st) => const LoginScreen(),
      ),
    );
  }
}
