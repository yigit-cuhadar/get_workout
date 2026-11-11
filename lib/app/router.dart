import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../features/account/presentation/account_page.dart';
import '../features/home/presentation/home_page.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const startFailed = '/start-failed';
  static const home = '/';
  static const account = '/account';

  /// Opens in sign-up mode; [accountSignIn] opens it in sign-in mode.
  static const accountAuth = '/account/auth';
  static const accountSignIn = '$accountAuth?mode=sign-in';
}

/// All routes live here. There is always a user (a guest until they create
/// an account), so the only gates are the splash while the session resolves
/// and a retry screen when the guest sign-in failed.
GoRouter buildRouter(AuthCubit auth) {
  return GoRouter(
    initialLocation: Routes.splash,
    // Refresh only when the redirect can change. A refresh re-parses the
    // current location; if it lands while a page pops itself on the same
    // auth change (AuthPage.onSignedIn), it restores that page.
    refreshListenable: _StreamListenable(
      auth.stream.map((state) => state.runtimeType).distinct(),
    ),
    redirect: (context, state) {
      final atGate =
          state.matchedLocation == Routes.splash ||
          state.matchedLocation == Routes.startFailed;
      return switch (auth.state) {
        AuthUnknown() => Routes.splash,
        Unauthenticated() => Routes.startFailed,
        Authenticated() => atGate ? Routes.home : null,
      };
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const Scaffold(body: LoadingView()),
      ),
      GoRoute(
        path: Routes.startFailed,
        builder: (_, _) => Scaffold(
          body: ErrorView(
            message: "Couldn't start. Check your connection and try again.",
            onRetry: auth.retryGuestSignIn,
          ),
        ),
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
