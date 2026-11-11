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
import '../features/profile/domain/user_profile.dart';
import '../features/profile/presentation/onboarding_page.dart';
import '../features/profile/presentation/profile_cubit.dart';
import '../features/profile/presentation/profile_details_page.dart';
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
  static const onboarding = '/onboarding';

  /// Where finishing or skipping onboarding lands. The program suggestion
  /// (programs catalogue) plugs in here.
  static const afterOnboarding = today;

  static const today = '/today';
  static const programs = '/programs';
  static const exercises = '/exercises';
  static const progress = '/progress';
  static const profile = '/profile';
  static const account = '$profile/account';

  /// Opens in sign-up mode; [accountSignIn] opens it in sign-in mode.
  static const accountAuth = '$account/auth';
  static const accountSignIn = '$accountAuth?mode=sign-in';

  static const profileDetails = '$profile/details';
  static String profileQuestion(ProfileField field) =>
      '$profileDetails/${field.name}';

  static const calculators = '$profile/calculators';
  static const calories = '$calculators/calories';
  static const bodyFat = '$calculators/body-fat';
  static const oneRepMax = '$calculators/one-rep-max';
  static const plates = '$calculators/plates';
  static const macros = '$calculators/macros';
  static const bodyIndices = '$calculators/bmi-ffmi';
}

/// All routes live here. There is always a user (a guest until they create
/// an account), so the gates are the splash while the session and then the
/// user's profile resolve, a retry screen when the guest sign-in failed, and
/// onboarding until the profile records it as completed.
GoRouter buildRouter(AuthCubit auth, ProfileCubit profile) {
  return GoRouter(
    initialLocation: Routes.splash,
    // Refresh only when the redirect can change. A refresh re-parses the
    // current location; if it lands while a page pops itself on the same
    // auth change (AuthPage.onSignedIn), it restores that page. A pending
    // profile never changes the redirect, so a user change between two
    // onboarded users (linking keeps the uid; signing in to an existing
    // account does not) refreshes nothing.
    refreshListenable: Listenable.merge([
      _StreamListenable(
        auth.stream.map((state) => state.runtimeType).distinct(),
      ),
      _StreamListenable(
        profile.stream
            .map(_profileGate)
            .where((gate) => gate != _ProfileGate.pending)
            .distinct(),
      ),
    ]),
    redirect: (context, state) {
      final location = state.matchedLocation;
      final atGate =
          location == Routes.splash || location == Routes.startFailed;
      final atOnboarding = location == Routes.onboarding;
      return switch (auth.state) {
        AuthUnknown() => Routes.splash,
        Unauthenticated() => Routes.startFailed,
        Authenticated(:final user) => switch (_profileGate(
          profile.state,
          uid: user.id,
        )) {
          // Wait for the first snapshot, so a returning user never sees
          // onboarding flash. Someone already in the app stays where they are.
          _ProfileGate.pending =>
            location == Routes.startFailed ? Routes.splash : null,
          _ProfileGate.onboarding => atOnboarding ? null : Routes.onboarding,
          // Includes a profile that could not be read: never trap the user.
          _ProfileGate.ready =>
            atGate
                ? Routes.home
                : atOnboarding
                ? Routes.afterOnboarding
                : null,
        },
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
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingPage(),
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
                path: 'details',
                builder: (_, _) => const ProfileDetailsPage(),
                routes: [
                  GoRoute(
                    path: ':field',
                    redirect: (_, state) =>
                        _field(state) == null ? Routes.profileDetails : null,
                    builder: (_, state) => ProfileQuestionPage(_field(state)!),
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

enum _ProfileGate { pending, onboarding, ready }

/// What the profile means for the redirect. [uid] is the signed-in user; a
/// profile of anyone else (the cubit has not caught up yet) is pending.
_ProfileGate _profileGate(ProfileState state, {String? uid}) {
  if (uid != null && state.uid != uid) return _ProfileGate.pending;
  return switch (state.status) {
    ProfileStatus.loading => _ProfileGate.pending,
    ProfileStatus.unavailable => _ProfileGate.ready,
    ProfileStatus.loaded =>
      state.profile.onboardingCompleted
          ? _ProfileGate.ready
          : _ProfileGate.onboarding,
  };
}

ProfileField? _field(GoRouterState state) =>
    ProfileField.values.asNameMap()[state.pathParameters['field']];

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
