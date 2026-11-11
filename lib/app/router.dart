import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_page.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const auth = '/auth';
  static const home = '/';
}

/// All routes live here. Signed-out users only ever see [Routes.auth].
GoRouter buildRouter(AuthCubit auth) {
  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: _StreamListenable(auth.stream),
    redirect: (context, state) {
      final atGate =
          state.matchedLocation == Routes.auth ||
          state.matchedLocation == Routes.splash;
      return switch (auth.state) {
        AuthUnknown() => Routes.splash,
        Unauthenticated() => Routes.auth,
        Authenticated() => atGate ? Routes.home : null,
      };
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const Scaffold(body: LoadingView()),
      ),
      GoRoute(path: Routes.auth, builder: (_, _) => const AuthPage()),
      GoRoute(path: Routes.home, builder: (_, _) => const HomePage()),
    ],
  );
}

class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<Object?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
