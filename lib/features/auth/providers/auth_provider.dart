import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Auth state — signed-in user for the shell, or null on login.
///
/// Emits [Auth.currentSession] once on subscribe, then every [onAuthStateChange]
/// event, so email/password sign-up with an immediate session updates the UI
/// without waiting on stream timing edge cases.
final authStateProvider = StreamProvider<User?>((ref) {
  final auth = Supabase.instance.client.auth;
  final controller = StreamController<User?>();

  void push(User? user) {
    if (!controller.isClosed) controller.add(user);
  }

  push(auth.currentSession?.user);

  final sub = auth.onAuthStateChange.listen((AuthState data) {
    push(data.session?.user);
  });

  ref.onDispose(() {
    sub.cancel();
    unawaited(controller.close());
  });

  return controller.stream;
});
