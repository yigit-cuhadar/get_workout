import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../features/account/presentation/account_page.dart';
import '../features/account/presentation/auth_strings.dart';
import '../features/cardio/presentation/cardio_form_page.dart';
import '../features/cardio/presentation/cardio_list_page.dart';
import '../features/calculators/presentation/body_fat_page.dart';
import '../features/calculators/presentation/body_indices_page.dart';
import '../features/calculators/presentation/calculators_page.dart';
import '../features/calculators/presentation/calories_page.dart';
import '../features/calculators/presentation/macros_page.dart';
import '../features/calculators/presentation/one_rep_max_page.dart';
import '../features/calculators/presentation/plates_page.dart';
import '../features/exercises/presentation/exercise_detail_page.dart';
import '../features/exercises/presentation/exercises_page.dart';
import '../features/profile/domain/user_profile.dart';
import '../features/profile/presentation/onboarding_page.dart';
import '../features/profile/presentation/profile_cubit.dart';
import '../features/profile/presentation/profile_details_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/programs/presentation/exercise_picker_page.dart';
import '../features/programs/presentation/program_builder_page.dart';
import '../features/programs/presentation/program_detail_page.dart';
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

  /// For a returning user; the account's profile then decides whether
  /// onboarding is still needed.
  static const onboardingSignIn = '$onboarding/sign-in';

  /// Where finishing or skipping onboarding lands. The program suggestion
  /// (programs catalogue) plugs in here.
  static const afterOnboarding = today;

  static const today = '/today';
  static const programs = '/programs';
  static const programNew = '$programs/new';
  static String program(String id) => '$programs/${Uri.encodeComponent(id)}';
  static String programEdit(String id) => '${program(id)}/edit';

  /// Pops with the chosen exercises: up to [max], or with [multiple] off
  /// the one tapped.
  static String exercisePicker({required int max, required bool multiple}) =>
      '$programs/pick?max=$max&multiple=$multiple';
  static const exercises = '/exercises';
  static String exercise(String id) => '$exercises/${Uri.encodeComponent(id)}';
  static const progress = '/progress';
  static const cardio = '$progress/cardio';
  static const cardioNew = '$cardio/new';
  static String cardioSession(String id) => '$cardio/$id';
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
    // profile never changes the redirect; a new user's settled profile can,
    // even when its gate equals the previous user's (the splash after a
    // retried guest start), hence the uid in the key.
    refreshListenable: Listenable.merge([
      _StreamListenable(
        auth.stream.map((state) => state.runtimeType).distinct(),
      ),
      _StreamListenable(
        profile.stream
            .map((state) => (uid: state.uid, gate: _profileGate(state)))
            .where((key) => key.gate != _ProfileGate.pending)
            .distinct(),
      ),
    ]),
    redirect: (context, state) {
      final location = state.matchedLocation;
      final atGate =
          location == Routes.splash || location == Routes.startFailed;
      final atOnboarding =
          location == Routes.onboarding ||
          location.startsWith('${Routes.onboarding}/');
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
        routes: [
          GoRoute(
            path: 'sign-in',
            builder: (context, _) => AuthPage(
              strings: localizedAuthStrings(AppLocalizations.of(context)),
              initialSignUp: false,
              onSignedIn: () => context.pop(),
            ),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          _tab(Routes.today, const TodayPage()),
          _tab(
            Routes.programs,
            const ProgramsPage(),
            routes: [
              // Before ':id', which would match these too.
              GoRoute(
                path: 'new',
                builder: (_, _) => const ProgramBuilderPage(),
              ),
              GoRoute(
                path: 'pick',
                builder: (_, state) {
                  final query = state.uri.queryParameters;
                  final max = int.tryParse(query['max'] ?? '') ?? 1;
                  return ExercisePickerPage(
                    max: max < 1 ? 1 : max,
                    multiple: query['multiple'] == 'true',
                  );
                },
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    ProgramDetailPage(id: state.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => ProgramBuilderPage(
                      programId: state.pathParameters['id'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          _tab(
            Routes.exercises,
            const ExercisesPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    ExerciseDetailPage(exerciseId: state.pathParameters['id']!),
              ),
            ],
          ),
          _tab(
            Routes.progress,
            const ProgressPage(),
            routes: [
              GoRoute(
                path: 'cardio',
                builder: (_, _) => const CardioListPage(),
                routes: [
                  // Before ':id', which would match 'new' too.
                  GoRoute(
                    path: 'new',
                    builder: (_, _) => const CardioNewPage(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (_, state) =>
                        CardioSessionPage(id: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
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
