import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../core/unsaved_changes.dart';
import '../features/account/presentation/account_page.dart';
import '../features/account/presentation/auth_strings.dart';
import '../features/body/presentation/body_entry_page.dart';
import '../features/body/presentation/body_page.dart';
import '../features/body/presentation/measurement_day_page.dart';
import '../features/body/presentation/measurement_summary_page.dart';
import '../features/body/presentation/weight_form_page.dart';
import '../features/account/presentation/delete_account_page.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/cardio/presentation/cardio_form_page.dart';
import '../features/cardio/presentation/cardio_list_page.dart';
import '../features/calculators/presentation/body_fat_page.dart';
import '../features/calculators/presentation/body_indices_page.dart';
import '../features/calculators/presentation/calculators_page.dart';
import '../features/calculators/presentation/calories_page.dart';
import '../features/calculators/presentation/macros_page.dart';
import '../features/calculators/presentation/one_rep_max_page.dart';
import '../features/calculators/presentation/plates_page.dart';
import '../features/exercises/presentation/custom_exercise_form_page.dart';
import '../features/exercises/presentation/exercise_detail_page.dart';
import '../features/exercises/presentation/exercises_page.dart';
import '../features/generator/domain/generator_answers.dart';
import '../features/notifications/data/notification_payloads.dart';
import '../features/generator/presentation/generator_page.dart';
import '../features/generator/presentation/generator_preview_page.dart';
import '../features/profile/domain/user_profile.dart';
import '../features/profile/presentation/onboarding_page.dart';
import '../features/profile/presentation/profile_cubit.dart';
import '../features/profile/presentation/profile_details_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/programs/presentation/catalogue_detail_page.dart';
import '../features/programs/presentation/catalogue_page.dart';
import '../features/programs/presentation/exercise_picker_page.dart';
import '../features/programs/presentation/program_suggestion_page.dart';
import '../features/programs/presentation/program_builder_page.dart';
import '../features/programs/presentation/program_detail_page.dart';
import '../features/programs/presentation/programs_page.dart';
import '../features/progress/presentation/progress_page.dart';
import '../features/steps/presentation/steps_page.dart';
import '../features/strength/presentation/exercise_strength_page.dart';
import '../features/strength/presentation/strength_list_page.dart';
import '../features/subscription/presentation/paywall_page.dart';
import '../features/today/presentation/today_page.dart';
import '../features/volume/presentation/volume_page.dart';
import '../features/workout/presentation/history_page.dart';
import '../features/workout/presentation/workout_detail_page.dart';
import '../features/workout/presentation/workout_edit_page.dart';
import '../features/workout/presentation/workout_page.dart';
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

  /// Where finishing or skipping onboarding lands: a suggested program,
  /// which goes on to Today.
  static const afterOnboarding = '/suggested-program';

  static const today = '/today';
  static const programs = '/programs';
  static const programNew = '$programs/new';
  static const catalogue = '$programs/catalogue';
  static const programGenerator = '$programs/generate';

  /// Push it with the `GeneratorAnswers` as `extra`; without them it goes
  /// back to the questions.
  static const programGeneratorPreview = '$programGenerator/preview';
  static String catalogueProgram(String id) =>
      '$catalogue/${Uri.encodeComponent(id)}';

  /// An exercise of a ready-made program, opened inside the Programs tab.
  static String catalogueExercise(String programId, String exerciseId) =>
      '${catalogueProgram(programId)}/exercises/'
      '${Uri.encodeComponent(exerciseId)}';

  /// [created]: the program was just stored; see [ProgramDetailPage.created].
  static String program(String id, {bool created = false}) =>
      '$programs/${Uri.encodeComponent(id)}${created ? '?created=true' : ''}';
  static String programEdit(String id) =>
      '$programs/${Uri.encodeComponent(id)}/edit';

  /// Pops with the chosen exercises: up to [max], or with [multiple] off
  /// the one tapped.
  static String exercisePicker({required int max, required bool multiple}) =>
      '$programs/pick?max=$max&multiple=$multiple';
  static const exercises = '/exercises';
  static String exercise(String id) => '$exercises/${Uri.encodeComponent(id)}';

  /// No exercise id is `new`: catalogue ids start with `ex_`, custom ones
  /// with `custom_`.
  static const customExerciseNew = '$exercises/new';
  static String customExerciseEdit(String id) => '${exercise(id)}/edit';
  static const progress = '/progress';
  static const cardio = '$progress/cardio';
  static const cardioNew = '$cardio/new';
  static String cardioSession(String id) => '$cardio/$id';
  static const history = '$progress/history';
  static const steps = '$progress/steps';
  static const volume = '$progress/volume';
  static const strength = '$progress/$strengthSegment';
  static String strengthExercise(String exerciseId) =>
      '$strength/${Uri.encodeComponent(exerciseId)}';

  /// An exercise's strength page above [exerciseLocation], where its detail
  /// page is open.
  static String exerciseStrength(String exerciseLocation) =>
      '$exerciseLocation/$strengthSegment';
  static const strengthSegment = 'strength';
  static const calendar = '$progress/calendar';
  static const body = '$progress/body';
  static const bodyWeightNew = '$body/weight';
  static const bodyMeasureNew = '$body/measure';
  static String bodySummary(String id) =>
      '$body/summary/${Uri.encodeComponent(id)}';
  static String bodyEntry(String id) => '$body/${Uri.encodeComponent(id)}';
  static String bodyEntryCompare(String id) => '${bodyEntry(id)}/compare';
  static String bodyEntryWeight(String id) => '${bodyEntry(id)}/weight';
  static String bodyEntryMeasure(String id) => '${bodyEntry(id)}/measure';

  /// Adds a past workout.
  static const historyNew = '$history/new';

  /// [exercisePicker] above a workout being edited.
  static String historyPicker({required int max, required bool multiple}) =>
      '$history/pick?max=$max&multiple=$multiple';
  static String historyWorkout(String id) =>
      '$history/${Uri.encodeComponent(id)}';
  static String historyEdit(String id) => '${historyWorkout(id)}/edit';
  static const profile = '/profile';

  /// The workout in progress, full screen above the tabs; push it so going
  /// back minimizes it.
  static const workout = '/workout';

  /// [exercisePicker] above the workout.
  static String workoutPicker({required int max, required bool multiple}) =>
      '$workout/pick?max=$max&multiple=$multiple';
  static const account = '$profile/account';

  /// Opens in sign-up mode; [accountSignIn] opens it in sign-in mode.
  static const accountAuth = '$account/auth';
  static const accountSignIn = '$accountAuth?mode=sign-in';
  static const accountDelete = '$account/delete';

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

  /// Full-screen over the tabs; push it, it pops when done. Premium
  /// features go through `context.requirePremium()` instead.
  static const paywall = '/paywall';
}

/// Whether [location] is past the start (splash, retry, onboarding and the
/// program suggested after it), where the app leads the way and a
/// notification tap waits.
bool isPastStart(String location) =>
    location.isNotEmpty &&
    location != Routes.splash &&
    location != Routes.startFailed &&
    location != Routes.afterOnboarding &&
    location != Routes.onboarding &&
    !location.startsWith('${Routes.onboarding}/');

/// The locations of the pages open in [stack], bottom first: those gone to
/// and those pushed above them, so the one in front is last. The stack's
/// own `uri` misses the pushed ones.
List<String> openLocations(RouteMatchList stack) {
  final open = <String>[];
  void visit(List<RouteMatchBase> matches) {
    for (final match in matches) {
      switch (match) {
        case ShellRouteMatch():
          visit(match.matches);
        case RouteMatch():
          open.add(match.matchedLocation);
      }
    }
  }

  visit(stack.matches);
  return open;
}

/// Whether the workout page, or one above it, is among the [open] pages.
bool _workoutOpen(List<String> open) => open.any(
  (location) =>
      location == Routes.workout || location.startsWith('${Routes.workout}/'),
);

/// Where a tap on a notification about [target] leads with the [open]
/// pages (see [openLocations]), or null to stay: a workout reminder leaves
/// the workout in progress open, wherever it is in the stack.
String? notificationDestination(NotificationTarget target, List<String> open) =>
    switch (target) {
      NotificationTarget.workout => _workoutOpen(open) ? null : Routes.today,
      NotificationTarget.announcement => Routes.today,
      // A new measurement day, unless one is already open.
      NotificationTarget.measurement =>
        open.contains(Routes.bodyMeasureNew) ? null : Routes.bodyMeasureNew,
    };

/// Where a tap on the workout's lock-screen activity or notification leads
/// with the [open] pages: the workout, pushed like from its bar so going
/// back minimizes it, or null to stay: it is open already (also under a
/// page pushed above it), or no workout is in progress any more (one left
/// behind), where the tap only opens the app.
String? lockScreenDestination(List<String> open, {required bool inProgress}) =>
    !inProgress || _workoutOpen(open) ? null : Routes.workout;

/// The sign-in providers offered next to email. Apple joins once the app is
/// signed by a paid Apple Developer team (the Sign in with Apple
/// entitlement); the App Store requires it wherever Google is offered.
const socialProviders = [SocialProvider.google];

/// All routes live here. There is always a user (a guest until they create
/// an account), so the gates are the splash while the session and then the
/// user's profile resolve, a retry screen when the guest sign-in failed, and
/// onboarding until the profile records it as completed.
/// [profileDebugSection] ends the Profile tab in debug builds. While
/// [deletionUnderway], nobody is moved: the deleted profile must not open
/// onboarding before the user is signed out.
GoRouter buildRouter(
  AuthCubit auth,
  ProfileCubit profile, {
  ValueListenable<bool>? deletionUnderway,
  Widget? profileDebugSection,
}) {
  // Who onboarding was last shown to.
  String? onboardingUid;
  final unsavedChanges = UnsavedChanges();
  return GoRouter(
    initialLocation: Routes.splash,
    onEnter: unsavedChanges.onEnter,
    // Refresh only when the redirect can change. A refresh re-parses the
    // current location; if it lands while a page pops itself on the same
    // auth change (AuthPage.onSignedIn), it restores that page. A pending
    // profile never changes the redirect; a new user's settled profile can,
    // even when its gate equals the previous user's (the splash after a
    // retried guest start), hence the uid in the key.
    refreshListenable: Listenable.merge([
      deletionUnderway,
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
      if (deletionUnderway?.value ?? false) return null;
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
          _ProfileGate.onboarding => () {
            onboardingUid = user.id;
            return atOnboarding ? null : Routes.onboarding;
          }(),
          // Includes a profile that could not be read: never trap the user.
          // Signing in from onboarding to an account already onboarded is
          // no onboarding done here.
          _ProfileGate.ready =>
            atOnboarding && user.id == onboardingUid
                ? Routes.afterOnboarding
                : atGate || atOnboarding
                ? Routes.home
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
              providers: socialProviders,
              initialSignUp: false,
              onSignedIn: () => context.pop(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.afterOnboarding,
        builder: (_, _) => const ProgramSuggestionPage(),
      ),
      GoRoute(
        path: Routes.workout,
        builder: (_, _) => const WorkoutPage(),
        routes: [GoRoute(path: 'pick', builder: (_, state) => _picker(state))],
      ),
      GoRoute(
        path: Routes.paywall,
        pageBuilder: (_, _) =>
            const MaterialPage(fullscreenDialog: true, child: PaywallPage()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => RepositoryProvider.value(
          value: unsavedChanges,
          child: AppShell(shell: shell),
        ),
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
              GoRoute(path: 'pick', builder: (_, state) => _picker(state)),
              GoRoute(
                path: 'generate',
                builder: (_, _) => const GeneratorPage(),
                routes: [
                  GoRoute(
                    path: 'preview',
                    redirect: (_, state) => state.extra is GeneratorAnswers
                        ? null
                        : Routes.programGenerator,
                    builder: (_, state) => GeneratorPreviewPage(
                      answers: state.extra! as GeneratorAnswers,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'catalogue',
                builder: (_, _) => const CataloguePage(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) =>
                        CatalogueDetailPage(id: state.pathParameters['id']!),
                    routes: [
                      GoRoute(
                        path: 'exercises/:exerciseId',
                        builder: (_, state) => ExerciseDetailPage(
                          exerciseId: state.pathParameters['exerciseId']!,
                          exerciseRoute: (exerciseId) =>
                              Routes.catalogueExercise(
                                state.pathParameters['id']!,
                                exerciseId,
                              ),
                        ),
                        routes: [
                          _exerciseStrength(
                            (state) => state.pathParameters['exerciseId']!,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) => ProgramDetailPage(
                  id: state.pathParameters['id']!,
                  created: state.uri.queryParameters['created'] == 'true',
                ),
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
              // Before ':id', which would match 'new' too.
              GoRoute(
                path: 'new',
                builder: (_, _) => const CustomExerciseNewPage(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) => ExerciseDetailPage(
                  exerciseId: state.pathParameters['id']!,
                  exerciseRoute: Routes.exercise,
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => CustomExerciseEditPage(
                      exerciseId: state.pathParameters['id']!,
                    ),
                  ),
                  _exerciseStrength((state) => state.pathParameters['id']!),
                ],
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
              GoRoute(path: 'volume', builder: (_, _) => const VolumePage()),
              GoRoute(
                path: Routes.strengthSegment,
                builder: (_, _) => const StrengthListPage(),
                routes: [
                  GoRoute(
                    path: ':exerciseId',
                    builder: (_, state) => ExerciseStrengthPage(
                      exerciseId: state.pathParameters['exerciseId']!,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'calendar',
                builder: (_, _) => const CalendarPage(),
              ),
              GoRoute(path: 'steps', builder: (_, _) => const StepsPage()),
              GoRoute(
                path: 'body',
                builder: (_, _) => const BodyPage(),
                routes: [
                  // Before ':id', which would match these too; entry ids
                  // are Firestore auto ids.
                  GoRoute(
                    path: 'weight',
                    builder: (_, _) => const WeightNewPage(),
                  ),
                  GoRoute(
                    path: 'measure',
                    builder: (_, _) => const MeasurementDayNewPage(),
                  ),
                  // Right after a new measurement day is saved.
                  GoRoute(
                    path: 'summary/:id',
                    builder: (_, state) => MeasurementSummaryPage(
                      id: state.pathParameters['id']!,
                      compare: false,
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (_, state) =>
                        BodyEntryPage(id: state.pathParameters['id']!),
                    routes: [
                      GoRoute(
                        path: 'weight',
                        builder: (_, state) =>
                            WeightEditPage(id: state.pathParameters['id']!),
                      ),
                      GoRoute(
                        path: 'measure',
                        builder: (_, state) => MeasurementDayEditPage(
                          id: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'compare',
                        builder: (_, state) => MeasurementSummaryPage(
                          id: state.pathParameters['id']!,
                          compare: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              GoRoute(
                path: 'history',
                builder: (_, _) => const HistoryPage(),
                routes: [
                  // Before ':id', which would match these too.
                  GoRoute(
                    path: 'new',
                    builder: (_, _) => const WorkoutEditPage(),
                  ),
                  GoRoute(path: 'pick', builder: (_, state) => _picker(state)),
                  GoRoute(
                    path: ':id',
                    builder: (_, state) =>
                        WorkoutDetailPage(id: state.pathParameters['id']!),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (_, state) =>
                            WorkoutEditPage(id: state.pathParameters['id']),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          _tab(
            Routes.profile,
            ProfilePage(debugSection: profileDebugSection),
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
                      providers: socialProviders,
                      initialSignUp:
                          state.uri.queryParameters['mode'] != 'sign-in',
                      onSignedIn: () => context.pop(),
                    ),
                  ),
                  GoRoute(
                    path: 'delete',
                    builder: (_, _) => const DeleteAccountPage(),
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

ExercisePickerPage _picker(GoRouterState state) {
  final query = state.uri.queryParameters;
  final max = int.tryParse(query['max'] ?? '') ?? 1;
  return ExercisePickerPage(
    max: max < 1 ? 1 : max,
    multiple: query['multiple'] == 'true',
  );
}

/// An exercise's strength page above its detail page, in the tab
/// showing that, so going back returns to the exercise.
GoRoute _exerciseStrength(String Function(GoRouterState state) exerciseId) =>
    GoRoute(
      path: Routes.strengthSegment,
      builder: (_, state) =>
          ExerciseStrengthPage(exerciseId: exerciseId(state)),
    );

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
