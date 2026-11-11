import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../features/account/presentation/account_page.dart';
import '../features/home/presentation/home_page.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const home = '/';
  static const account = '/account';

  /// Opens in sign-up mode; [accountSignIn] opens it in sign-in mode.
  static const accountAuth = '/account/auth';
  static const accountSignIn = '$accountAuth?mode=sign-in';
}

/// All routes live here. There is always a user (a guest until they create
/// an account), so the only gate is the splash while the session resolves.
GoRouter buildRouter(AuthCubit auth) {
  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: _StreamListenable(auth.stream),
    redirect: (context, state) => switch (auth.state) {
      AuthUnknown() || Unauthenticated() => Routes.splash,
      Authenticated() =>
        state.matchedLocation == Routes.splash ? Routes.home : null,
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const Scaffold(body: LoadingView()),
      ),
      GoRoute(path: Routes.home, builder: (_, _) => const HomePage()),
      GoRoute(
        path: Routes.account,
        builder: (_, _) => const AccountPage(),
        routes: [
          GoRoute(
            path: 'auth',
            builder: (context, state) => AuthPage(
              initialSignUp: state.uri.queryParameters['mode'] != 'sign-in',
              onSignedIn: () => context.pop(),
            ),
          ),
        ],
      ),
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
