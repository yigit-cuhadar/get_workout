import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../features/account/presentation/account_page.dart';
import '../features/account/presentation/auth_strings.dart';
import '../features/calculators/presentation/body_fat_page.dart';
import '../features/calculators/presentation/body_indices_page.dart';
import '../features/calculators/presentation/calculators_page.dart';
import '../features/calculators/presentation/calories_page.dart';
import '../features/calculators/presentation/macros_page.dart';
import '../features/calculators/presentation/one_rep_max_page.dart';
import '../features/calculators/presentation/plates_page.dart';
import '../features/exercises/presentation/exercises_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/programs/presentation/programs_page.dart';
import '../features/progress/presentation/progress_page.dart';
import '../features/today/presentation/today_page.dart';
import '../l10n/app_localizations.dart';
import 'app_shell.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const startFailed = '/start-failed';
  static const home = today;

  static const today = '/today';
  static const programs = '/programs';
  static const exercises = '/exercises';
  static const progress = '/progress';
  static const profile = '/profile';
  static const account = '$profile/account';

  /// Opens in sign-up mode; [accountSignIn] opens it in sign-in mode.
  static const accountAuth = '$account/auth';
  static const accountSignIn = '$accountAuth?mode=sign-in';

  static const calculators = '$profile/calculators';
  static const calories = '$calculators/calories';
  static const bodyFat = '$calculators/body-fat';
  static const oneRepMax = '$calculators/one-rep-max';
  static const plates = '$calculators/plates';
  static const macros = '$calculators/macros';
  static const bodyIndices = '$calculators/bmi-ffmi';
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
      GoRoute(path: '/', redirect: (_, _) => Routes.home),
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const Scaffold(body: LoadingView()),
      ),
      GoRoute(
        path: Routes.startFailed,
        builder: (context, _) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            body: ErrorView(
              message: l10n.startFailed,
              retryLabel: l10n.retry,
              onRetry: auth.retryGuestSignIn,
            ),
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          _tab(Routes.today, const TodayPage()),
          _tab(Routes.programs, const ProgramsPage()),
          _tab(Routes.exercises, const ExercisesPage()),
          _tab(Routes.progress, const ProgressPage()),
          _tab(
            Routes.profile,
            const ProfilePage(),
            routes: [
              GoRoute(
                path: 'account',
                builder: (_, _) => const AccountPage(),
                routes: [
                  GoRoute(
                    path: 'auth',
                    builder: (context, state) => AuthPage(
                      strings: localizedAuthStrings(
                        AppLocalizations.of(context),
                      ),
                      initialSignUp:
                          state.uri.queryParameters['mode'] != 'sign-in',
                      onSignedIn: () => context.pop(),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'calculators',
                builder: (_, _) => const CalculatorsPage(),
                routes: [
                  _page('calories', const CaloriesPage()),
                  _page('body-fat', const BodyFatPage()),
                  _page('one-rep-max', const OneRepMaxPage()),
                  _page('plates', const PlatesPage()),
                  _page('macros', const MacrosPage()),
                  _page('bmi-ffmi', const BodyIndicesPage()),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

GoRoute _page(String path, Widget page) =>
    GoRoute(path: path, builder: (_, _) => page);

StatefulShellBranch _tab(
  String path,
  Widget page, {
  List<RouteBase> routes = const [],
}) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (_, _) => page, routes: routes)],
);

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
