import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:go_router/go_router.dart';

import '../core/pages.dart';
import '../core/unsaved_changes.dart';
import '../features/account/presentation/account_page.dart';
import '../features/account/presentation/account_auth_page.dart';
import '../features/body/presentation/body_entry_page.dart';
import '../features/body/presentation/body_page.dart';
import '../features/body/presentation/measurement_day_page.dart';
import '../features/body/presentation/measurement_summary_page.dart';
import '../features/account/presentation/delete_account_page.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/cardio/presentation/cardio_form_page.dart';
import '../features/cardio/presentation/cardio_session_page.dart';
import '../features/cardio/presentation/cardio_list_page.dart';
import '../features/calculators/presentation/bar_plates_page.dart';
import '../features/calculators/presentation/body_fat_page.dart';
import '../features/calculators/presentation/body_indices_page.dart';
import '../features/calculators/presentation/calculators_page.dart';
import '../features/calculators/presentation/calories_page.dart';
import '../features/calculators/presentation/macros_page.dart';
import '../features/calculators/presentation/one_rep_max_page.dart';
import '../features/calculators/presentation/plates_page.dart';
import '../features/exercises/presentation/custom_exercise_form_page.dart';
import '../features/exercises/domain/vocabulary.dart';
import '../features/exercises/presentation/exercise_detail_page.dart';
import '../features/exercises/presentation/exercises_page.dart';
import '../features/exercises/presentation/library_page.dart';
import '../features/generator/domain/generator_answers.dart';
import '../features/notifications/data/notification_payloads.dart';
import '../features/generator/presentation/generator_page.dart';
import '../features/generator/presentation/generator_preview_page.dart';
import '../features/profile/domain/user_profile.dart';
import '../features/profile/presentation/onboarding_page.dart';
import '../features/profile/presentation/onboarding_permissions_page.dart';
import '../features/profile/presentation/profile_cubit.dart';
import '../features/profile/presentation/profile_details_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/programs/domain/program.dart';
import '../features/programs/presentation/catalogue_detail_page.dart';
import '../features/programs/presentation/catalogue_page.dart';
import '../features/programs/presentation/exercise_picker_page.dart';
import '../features/programs/presentation/program_suggestion_page.dart';
import '../features/programs/presentation/program_volume_page.dart';
import '../features/programs/presentation/program_builder_page.dart';
import '../features/programs/presentation/program_detail_page.dart';
import '../features/programs/presentation/programs_page.dart';
import '../features/progress/presentation/progress_page.dart';
import '../features/settings/presentation/gesture_lab/gesture_lab_page.dart';
import '../features/settings/presentation/gesture_lab/scroll_lab_page.dart';
import '../features/settings/presentation/warmup_settings_page.dart';
import '../features/steps/presentation/steps_page.dart';
import '../features/strength/presentation/exercise_strength_page.dart';
import '../features/strength/presentation/strength_list_page.dart';
import '../features/subscription/presentation/paywall_page.dart';
import '../features/today/presentation/today_page.dart';
import '../features/volume/presentation/volume_page.dart';
import '../features/workout/domain/workout.dart';
import '../features/workout/presentation/workout_detail_page.dart';
import '../features/workout/domain/workout_editing.dart';
import '../features/workout/presentation/workout_edit_page.dart';
import '../features/workout/presentation/workout_page.dart';
import 'app_shell.dart';
import 'splash.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const startFailed = '/start-failed';
  static const home = today;
  static const onboarding = '/onboarding';

  /// For a returning user; the account's profile then decides whether
  /// onboarding is still needed.
  static const onboardingSignIn = '$onboarding/sign-in';

  /// Where finishing onboarding lands: a suggested program, which goes on
  /// to Today. Skipping it lands on Today.
  static const afterOnboarding = '/suggested-program';

  static const today = '/today';

  /// A finished workout above Today, so Back returns there.
  static String todayWorkout(String id) =>
      '$today/workouts/${Uri.encodeComponent(id)}';
  static String todayWorkoutEdit(String id) => '${todayWorkout(id)}/edit';
  static String todayPicker({required int max, required bool multiple}) =>
      '$today/pick?max=$max&multiple=$multiple';
  static String todayExercise(String id) =>
      '$today/exercises/${Uri.encodeComponent(id)}';

  /// A stored workout edited in Today's tab.
  static const WorkoutEditRoutes todayEditing = (
    edit: todayWorkoutEdit,
    picker: todayPicker,
    exercise: todayExercise,
  );

  /// A stored workout edited in the calendar's.
  static const WorkoutEditRoutes calendarEditing = (
    edit: calendarWorkoutEdit,
    picker: calendarPicker,
    exercise: calendarExercise,
  );
  static const programs = '/programs';
  static const programNew = '$programs/new';

  /// [programNew] pushed above a page in the Programs tab, which saving or
  /// leaving it returns to.
  static const programNewReturning = '$programNew?return=true';
  static const catalogue = '$programs/catalogue';

  /// The generator's questions, full screen above the tabs; pushed, so
  /// Back on the first question returns where it was opened.
  static const programGenerator = '/generate';

  /// Push it with the `GeneratorAnswers` as `extra`; without them it goes
  /// back to the questions.
  static const programGeneratorPreview = '$programGenerator/preview';

  static String catalogueProgram(String id) =>
      '$catalogue/${Uri.encodeComponent(id)}';

  /// A ready-made program's weekly sets per muscle.
  static String catalogueVolume(String id) => '${catalogueProgram(id)}/volume';

  /// An exercise of a ready-made program, opened inside the Programs tab.
  static String catalogueExercise(String programId, String exerciseId) =>
      '${catalogueProgram(programId)}/exercises/'
      '${Uri.encodeComponent(exerciseId)}';

  /// [created]: the program was just stored; see [ProgramDetailPage.created].
  static String program(String id, {bool created = false}) =>
      '$programs/${Uri.encodeComponent(id)}${created ? '?created=true' : ''}';

  /// A program's weekly sets per muscle, pushed above the Programs tab.
  static String programVolume(String id) =>
      '$programs/volume/${Uri.encodeComponent(id)}';
  static String programEdit(String id) =>
      '$programs/${Uri.encodeComponent(id)}/edit';

  /// Pops with the chosen exercises: up to [max], or with [multiple] off
  /// the one tapped.
  static String exercisePicker({required int max, required bool multiple}) =>
      '$programs/pick?max=$max&multiple=$multiple';

  /// The exercise picker above the generator, for the exercises it leaves
  /// out; see [exercisePicker].
  static String exerciseLeaveOutPicker(int max) =>
      '$programGenerator/pick?max=$max&multiple=true&form=leaveOut';

  /// [exercisePicker] above the generator's preview.
  static String generatorPicker({required int max, required bool multiple}) =>
      '$programGenerator/pick?max=$max&multiple=$multiple';
  static const exercises = '/exercises';
  static String exercise(String id) => '$exercises/${Uri.encodeComponent(id)}';

  /// The exercise list above the Exercises tab's first page. No exercise id
  /// is `list`, `new` or `new-program`: catalogue ids start with `ex_`,
  /// custom ones with `custom_`.
  static const exerciseList = '$exercises/list';

  /// [exerciseList] browsing [muscle].
  static String exerciseListOf(Muscle muscle) =>
      '$exerciseList?muscle=${muscle.code}';
  static const customExerciseNew = '$exercises/new';

  /// [customExerciseNew] with its name filled in.
  static String customExerciseNamed(String name) =>
      Uri(path: customExerciseNew, queryParameters: {'name': name}).toString();
  static String customExerciseEdit(String id) => '${exercise(id)}/edit';

  /// [programNew] pushed above a page in the Exercises tab, which saving or
  /// leaving it returns to.
  static const exerciseProgramNew = '$exercises/new-program';

  /// [exercisePicker] above [exerciseProgramNew].
  static String exerciseProgramPicker({
    required int max,
    required bool multiple,
  }) => '$exerciseProgramNew/pick?max=$max&multiple=$multiple';
  static const progress = '/progress';
  static const cardio = '$progress/cardio';
  static const cardioNew = '$cardio/new';
  static String cardioSession(String id) => '$cardio/$id';
  static String cardioSessionEdit(String id) => '${cardioSession(id)}/edit';
  static const steps = '$progress/steps';
  static const volume = '$progress/volume';
  static const strength = '$progress/$strengthSegment';
  static String strengthExercise(String exerciseId) =>
      '$strength/${Uri.encodeComponent(exerciseId)}';
  static const strengthSegment = 'strength';
  static const calendar = '$progress/calendar';
  static const body = '$progress/body';
  static const bodyMeasureNew = '$body/measure';
  static String bodySummary(String id) =>
      '$body/summary/${Uri.encodeComponent(id)}';
  static String bodyEntry(String id) => '$body/${Uri.encodeComponent(id)}';

  /// The Body page on Compare, measurement day [id] the later one.
  static String bodyEntryCompare(String id) =>
      '$body?compare=${Uri.encodeQueryComponent(id)}';
  static String bodyEntryMeasure(String id) => '${bodyEntry(id)}/measure';

  /// Adds a past workout.
  static const calendarWorkoutNew = '$calendar/new';

  /// [exercisePicker] above a workout being edited.
  static String calendarPicker({required int max, required bool multiple}) =>
      '$calendar/pick?max=$max&multiple=$multiple';

  /// A finished workout, above the calendar.
  static String calendarWorkout(String id) =>
      '$calendar/${Uri.encodeComponent(id)}';
  static String calendarWorkoutEdit(String id) => '${calendarWorkout(id)}/edit';

  /// An exercise's detail page above a workout being edited.
  static String calendarExercise(String id) =>
      '$calendar/exercises/${Uri.encodeComponent(id)}';
  static const profile = '/profile';

  /// The workout in progress, full screen above the tabs; push it so going
  /// back minimizes it.
  static const workout = '/workout';

  /// [exercisePicker] above the workout.
  static String workoutPicker({required int max, required bool multiple}) =>
      '$workout/pick?max=$max&multiple=$multiple';

  /// An exercise's detail page above the workout.
  static String workoutExercise(String id) =>
      '$workout/exercises/${Uri.encodeComponent(id)}';
  static const account = '$profile/account';

  /// Opens in sign-up mode; [accountSignIn] opens it in sign-in mode.
  static const accountAuth = '$account/auth';
  static const accountSignIn = '$accountAuth?mode=sign-in';
  static const accountDelete = '$account/delete';

  /// The automatic warm-up sets, from the settings.
  static const warmupSettings = '$profile/warmups';

  /// The user's bars and plates, from the settings.
  static const barPlates = '$profile/bar-plates';

  static const profileDetails = '$profile/details';
  static String profileQuestion(ProfileField field) =>
      '$profileDetails/${field.name}';

  /// Developer tooling, never in a release build.
  static const gestureLab = '$profile/gesture-lab';
  static const gestureLabScroll = '$gestureLab/scroll';

  /// The calculators, a tool of the Today tab.
  static const calculators = '$today/calculators';
  static const calories = '$calculators/calories';
  static const bodyFat = '$calculators/body-fat';
  static const oneRepMax = '$calculators/one-rep-max';
  static const plates = '$calculators/plates';

  /// [barPlates] above the Plates calculator, in its tab.
  static const platesBarPlates = '$plates/bar-plates';
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

/// The program builder to push above the page at [location], in its tab,
/// so that saving or leaving it returns there: in the Programs or the
/// Exercises tab. Null elsewhere (above a workout, in another tab), where
/// the builder opens in the Programs tab instead.
String? returningProgramNew(String location) {
  bool under(String root) => location == root || location.startsWith('$root/');
  if (under(Routes.programs)) return Routes.programNewReturning;
  if (under(Routes.exercises)) return Routes.exerciseProgramNew;
  return null;
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

/// Where the summary of a workout that ended itself opens with the [open]
/// pages: the workout page, unless it is open already.
String? selfEndedDestination(List<String> open) =>
    _workoutOpen(open) ? null : Routes.workout;

/// All routes live here. There is always a user (a guest until they create
/// an account), so the gates are the splash while the session and then the
/// user's profile resolve, a retry screen when the guest sign-in failed, and
/// onboarding until the profile records it as completed.
/// [profileDevTools] end the Profile tab outside release builds. While
/// [deletionUnderway], nobody is moved: the deleted profile must not open
/// onboarding before the user is signed out.
GoRouter buildRouter(
  AuthCubit auth,
  ProfileCubit profile, {
  ValueListenable<bool>? deletionUnderway,
  List<Widget> profileDevTools = const [],
}) {
  // Who onboarding was last shown to.
  String? onboardingUid;
  final unsavedChanges = UnsavedChanges();
  final root = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: root,
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
      GoRoute(path: Routes.splash, builder: (_, _) => const AppSplash()),
      GoRoute(
        path: Routes.startFailed,
        builder: (_, _) => AppStartFailed(onRetry: auth.retryGuestSignIn),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingPage(),
        routes: [
          GoRoute(
            path: 'sign-in',
            pageBuilder: (context, state) => _pushed(
              state,
              AccountAuthPage(
                initialSignUp: false,
                onSignedIn: () => context.pop(),
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.afterOnboarding,
        builder: (_, _) =>
            const OnboardingPermissionsPage(next: ProgramSuggestionPage()),
      ),
      GoRoute(
        path: Routes.workout,
        pageBuilder: (_, state) => _pushed(state, const WorkoutPage()),
        routes: [
          _pickerRoute(limit: WorkoutLimits.maxExercises),
          _workoutExercise(Routes.workoutExercise),
        ],
      ),
      GoRoute(
        path: Routes.programGenerator,
        pageBuilder: (_, state) => _pushed(state, const GeneratorPage()),
        routes: [
          GoRoute(
            path: 'preview',
            redirect: (_, state) => state.extra is GeneratorAnswers
                ? null
                : Routes.programGenerator,
            pageBuilder: (_, state) => _pushed(
              state,
              GeneratorPreviewPage(answers: state.extra! as GeneratorAnswers),
            ),
          ),
          _pickerRoute(limit: ProgramLimits.maxItemsPerDay),
        ],
      ),
      GoRoute(
        path: Routes.paywall,
        pageBuilder: (context, state) =>
            _overFlow(context, state, const PaywallPage()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => RepositoryProvider.value(
          value: unsavedChanges,
          child: AppShell(shell: shell),
        ),
        branches: [
          _tab(
            Routes.today,
            const TodayPage(),
            routes: [
              _pickerRoute(limit: WorkoutLimits.maxExercises),
              _workoutExercise(Routes.todayExercise),
              GoRoute(
                path: 'workouts/:id',
                pageBuilder: (_, state) => _pushed(
                  state,
                  WorkoutDetailPage(
                    id: state.pathParameters['id']!,
                    routes: Routes.todayEditing,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      WorkoutEditPage(
                        id: state.pathParameters['id'],
                        routes: Routes.todayEditing,
                      ),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'calculators',
                pageBuilder: (_, state) =>
                    _pushed(state, const CalculatorsPage()),
                routes: [
                  _page('calories', const CaloriesPage()),
                  _page('body-fat', const BodyFatPage()),
                  _page('one-rep-max', const OneRepMaxPage()),
                  GoRoute(
                    path: 'plates',
                    pageBuilder: (_, state) =>
                        _pushed(state, const PlatesPage()),
                    routes: [_page('bar-plates', const BarPlatesPage())],
                  ),
                  _page('macros', const MacrosPage()),
                  _page('bmi-ffmi', const BodyIndicesPage()),
                ],
              ),
            ],
          ),
          _tab(
            Routes.programs,
            const ProgramsPage(),
            routes: [
              // Before ':id', which would match these too.
              GoRoute(
                path: 'new',
                pageBuilder: (_, state) => _pushed(
                  state,
                  ProgramBuilderPage(
                    returns: state.uri.queryParameters['return'] == 'true',
                  ),
                ),
              ),
              _pickerRoute(limit: ProgramLimits.maxItemsPerDay),
              GoRoute(
                path: 'catalogue',
                pageBuilder: (_, state) =>
                    _pushed(state, const CataloguePage()),
                routes: [
                  GoRoute(
                    path: ':id',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      CatalogueDetailPage(id: state.pathParameters['id']!),
                    ),
                    routes: [
                      GoRoute(
                        path: 'volume',
                        pageBuilder: (_, state) => _pushed(
                          state,
                          CatalogueVolumePage(id: state.pathParameters['id']!),
                        ),
                      ),
                      GoRoute(
                        path: 'exercises/:exerciseId',
                        pageBuilder: (_, state) => _pushed(
                          state,
                          ExerciseDetailPage(
                            exerciseId: state.pathParameters['exerciseId']!,
                            exerciseRoute: (exerciseId) =>
                                Routes.catalogueExercise(
                                  state.pathParameters['id']!,
                                  exerciseId,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Before ':id', which would match 'volume' too.
              GoRoute(
                path: 'volume/:id',
                pageBuilder: (_, state) => _pushed(
                  state,
                  ProgramVolumePage(id: state.pathParameters['id']!),
                ),
              ),
              GoRoute(
                path: ':id',
                pageBuilder: (_, state) => _pushed(
                  state,
                  ProgramDetailPage(
                    // Another program, e.g. a copy just made from this
                    // page, gets a page of its own, not this one's state.
                    key: ValueKey(state.pathParameters['id']),
                    id: state.pathParameters['id']!,
                    created: state.uri.queryParameters['created'] == 'true',
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      ProgramBuilderPage(programId: state.pathParameters['id']),
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
              // Before ':id', which would match these too.
              GoRoute(
                path: 'list',
                pageBuilder: (_, state) => _pushed(
                  state,
                  LibraryPage(
                    muscle: Muscle.values.byCode(
                      state.uri.queryParameters['muscle'],
                    ),
                  ),
                ),
              ),
              GoRoute(
                path: 'new',
                pageBuilder: (_, state) => _pushed(
                  state,
                  CustomExerciseNewPage(
                    name: state.uri.queryParameters['name'],
                  ),
                ),
              ),
              GoRoute(
                path: 'new-program',
                pageBuilder: (_, state) => _pushed(
                  state,
                  const ProgramBuilderPage(
                    returns: true,
                    picker: Routes.exerciseProgramPicker,
                  ),
                ),
                routes: [_pickerRoute(limit: ProgramLimits.maxItemsPerDay)],
              ),
              GoRoute(
                path: ':id',
                pageBuilder: (_, state) => _pushed(
                  state,
                  ExerciseDetailPage(
                    exerciseId: state.pathParameters['id']!,
                    exerciseRoute: Routes.exercise,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      CustomExerciseEditPage(
                        exerciseId: state.pathParameters['id']!,
                      ),
                    ),
                  ),
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
                pageBuilder: (_, state) =>
                    _pushed(state, const CardioListPage()),
                routes: [
                  // Before ':id', which would match 'new' too.
                  GoRoute(
                    path: 'new',
                    pageBuilder: (_, state) =>
                        _pushed(state, const CardioNewPage()),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      CardioSessionPage(id: state.pathParameters['id']!),
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        pageBuilder: (_, state) => _pushed(
                          state,
                          CardioEditPage(id: state.pathParameters['id']!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              GoRoute(
                path: 'volume',
                pageBuilder: (_, state) => _pushed(state, const VolumePage()),
              ),
              GoRoute(
                path: Routes.strengthSegment,
                pageBuilder: (_, state) =>
                    _pushed(state, const StrengthListPage()),
                routes: [
                  GoRoute(
                    path: ':exerciseId',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      ExerciseStrengthPage(
                        exerciseId: state.pathParameters['exerciseId']!,
                      ),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'calendar',
                pageBuilder: (_, state) => _pushed(state, const CalendarPage()),
                routes: [
                  // Before ':id', which would match these too.
                  GoRoute(
                    path: 'new',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      WorkoutEditPage(
                        plan: state.extra as PastWorkoutPlan?,
                        routes: Routes.calendarEditing,
                      ),
                    ),
                  ),
                  _pickerRoute(limit: WorkoutLimits.maxExercises),
                  _workoutExercise(Routes.calendarExercise),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      WorkoutDetailPage(
                        id: state.pathParameters['id']!,
                        routes: Routes.calendarEditing,
                      ),
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        pageBuilder: (_, state) => _pushed(
                          state,
                          WorkoutEditPage(
                            id: state.pathParameters['id'],
                            routes: Routes.calendarEditing,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              GoRoute(
                path: 'steps',
                pageBuilder: (_, state) => _pushed(state, const StepsPage()),
              ),
              GoRoute(
                path: 'body',
                // One page whatever the query, so a link to Compare reuses
                // the one there.
                pageBuilder: (_, state) => _pushed(
                  state,
                  BodyPage(compareAfter: state.uri.queryParameters['compare']),
                ),
                routes: [
                  // Before ':id', which would match these too; entry ids
                  // are Firestore auto ids.
                  GoRoute(
                    path: 'measure',
                    pageBuilder: (_, state) =>
                        _pushed(state, const MeasurementDayNewPage()),
                  ),
                  // Right after a new measurement day is saved.
                  GoRoute(
                    path: 'summary/:id',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      MeasurementSummaryPage(id: state.pathParameters['id']!),
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      BodyEntryPage(id: state.pathParameters['id']!),
                    ),
                    routes: [
                      GoRoute(
                        path: 'measure',
                        pageBuilder: (_, state) => _pushed(
                          state,
                          MeasurementDayEditPage(
                            id: state.pathParameters['id']!,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          _tab(
            Routes.profile,
            ProfilePage(devTools: profileDevTools),
            routes: [
              GoRoute(
                path: 'account',
                pageBuilder: (_, state) => _pushed(state, const AccountPage()),
                routes: [
                  GoRoute(
                    path: 'auth',
                    // Full screen, over the tab bar.
                    parentNavigatorKey: root,
                    pageBuilder: (context, state) => _pushed(
                      state,
                      AccountAuthPage(
                        initialSignUp:
                            state.uri.queryParameters['mode'] != 'sign-in',
                        onSignedIn: () => context.pop(),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'delete',
                    pageBuilder: (_, state) =>
                        _pushed(state, const DeleteAccountPage()),
                  ),
                ],
              ),
              GoRoute(
                path: 'bar-plates',
                pageBuilder: (_, state) =>
                    _pushed(state, const BarPlatesPage()),
              ),
              GoRoute(
                path: 'warmups',
                pageBuilder: (_, state) =>
                    _pushed(state, const WarmupSettingsPage()),
              ),
              if (!kReleaseMode)
                GoRoute(
                  path: 'gesture-lab',
                  pageBuilder: (_, state) =>
                      _pushed(state, const GestureLabPage()),
                  routes: [_page('scroll', const ScrollLabPage())],
                ),
              GoRoute(
                path: 'details',
                pageBuilder: (_, state) =>
                    _pushed(state, const ProfileDetailsPage()),
                routes: [
                  GoRoute(
                    path: ':field',
                    // Over the tab bar.
                    parentNavigatorKey: root,
                    redirect: (_, state) =>
                        _field(state) == null ? Routes.profileDetails : null,
                    pageBuilder: (_, state) =>
                        _pushed(state, ProfileQuestionPage(_field(state)!)),
                  ),
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
  if (state.status == ProfileStatus.loading) return _ProfileGate.pending;
  return state.pastOnboarding ? _ProfileGate.ready : _ProfileGate.onboarding;
}

ProfileField? _field(GoRouterState state) =>
    ProfileField.values.asNameMap()[state.pathParameters['field']];

/// The exercise picker of a page whose lists hold at most [limit]
/// exercises, with a custom exercise created above it. Adding opens over
/// the flow (close); Swap and Replace are steps of it (back).
GoRoute _pickerRoute({required int limit}) => GoRoute(
  path: 'pick',
  pageBuilder: (context, state) {
    final query = state.uri.queryParameters;
    final max = int.tryParse(query['max'] ?? '') ?? 1;
    final form = ExercisePickerForm.byName(query['form']);
    final page = ExercisePickerPage(
      max: max < 1 ? 1 : max,
      limit: limit,
      multiple: query['multiple'] == 'true',
      form: form,
      exerciseId: query['exercise'],
      logged: int.tryParse(query['logged'] ?? '') ?? 0,
      warmups: int.tryParse(query['warmups'] ?? '') ?? 0,
    );
    return form == ExercisePickerForm.add || form == ExercisePickerForm.leaveOut
        ? _overFlow(context, state, page)
        : _pushed(state, page);
  },
  routes: [
    GoRoute(
      path: 'new',
      pageBuilder: (_, state) => _pushed(
        state,
        CustomExerciseNewPage(name: state.uri.queryParameters['name']),
      ),
    ),
  ],
);

/// An exercise's detail page pushed above a workout (in progress or being
/// edited), so going back returns to it; [exerciseRoute] is where it opens
/// other exercises.
GoRoute _workoutExercise(String Function(String id) exerciseRoute) => GoRoute(
  path: 'exercises/:exerciseId',
  pageBuilder: (_, state) => _pushed(
    state,
    ExerciseDetailPage(
      exerciseId: state.pathParameters['exerciseId']!,
      exerciseRoute: exerciseRoute,
    ),
  ),
);

/// Every pushed page; see [AppPage]. go_router's own page for a `builder`
/// route has no transition here, so no back swipe: it looks for
/// material_ui's MaterialApp, which is not Flutter's.
Page<void> _pushed(GoRouterState state, Widget page) =>
    AppPage(key: state.pageKey, child: page);

/// A page opened over the flow, with close: on iOS a sheet that a drag
/// down closes, elsewhere a full-screen dialog.
Page<void> _overFlow(BuildContext context, GoRouterState state, Widget page) =>
    Theme.of(context).platform == TargetPlatform.iOS
    ? SheetPage(key: state.pageKey, child: page)
    : AppPage(key: state.pageKey, fullscreenDialog: true, child: page);

GoRoute _page(String path, Widget page) =>
    GoRoute(path: path, pageBuilder: (_, state) => _pushed(state, page));

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
