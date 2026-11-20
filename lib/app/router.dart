import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:go_router/go_router.dart';

import '../core/pages.dart';
import '../core/unsaved_changes.dart';
import '../features/account/presentation/account_page.dart';
import '../features/analytics/domain/analytics.dart';
import '../features/account/presentation/account_auth_page.dart';
import '../features/account/presentation/auth_strings.dart';
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
import '../features/feedback/domain/feedback.dart';
import '../features/feedback/presentation/feedback_page.dart';
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
import '../features/settings/presentation/warmup_settings_page.dart';
import '../features/steps/presentation/steps_page.dart';
import '../features/strength/presentation/exercise_strength_page.dart';
import '../features/strength/presentation/strength_list_page.dart';
import '../features/subscription/domain/paywall_moment.dart';
import '../features/subscription/presentation/paywall_page.dart';
import '../features/subscription/presentation/premium.dart';
import '../features/today/presentation/today_page.dart';
import '../features/volume/presentation/volume_page.dart';
import '../features/workout/domain/workout.dart';
import '../features/workout/presentation/workout_detail_page.dart';
import '../features/workout/domain/workout_editing.dart';
import '../features/workout/presentation/workout_edit_page.dart';
import '../features/workout/presentation/workout_page.dart';
import '../l10n/app_localizations.dart';
import 'app_shell.dart';
import 'splash.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const startFailed = '/start-failed';

  /// Stands in for the app while an email account's address is not
  /// verified.
  static const verifyEmail = '/verify-email';
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
  /// [onboarding]: opened from onboarding's suggestion, which starting it
  /// tells analytics.
  static String program(
    String id, {
    bool created = false,
    bool onboarding = false,
  }) {
    final query = [
      if (created) 'created=true',
      if (onboarding) 'from=onboarding',
    ];
    return '$programs/${Uri.encodeComponent(id)}'
        '${query.isEmpty ? '' : '?${query.join('&')}'}';
  }

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

  /// The workout in progress, risen from the bottom over the tabs
  /// ([RisingPage]); push it so closing it minimizes it.
  static const workout = '/workout';

  /// [exercisePicker] above the workout.
  static String workoutPicker({required int max, required bool multiple}) =>
      '$workout/pick?max=$max&multiple=$multiple';

  /// An exercise's detail page above the workout.
  static String workoutExercise(String id) =>
      '$workout/exercises/${Uri.encodeComponent(id)}';

  /// Help & feedback above the summary, from the review prompt.
  static const workoutFeedback = '$workout/feedback';

  /// Help & feedback above Today, from the review prompt.
  static const todayFeedback = '$today/feedback';
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

  /// Help & feedback, from the Profile tab.
  static const profileFeedback = '$profile/feedback';
  static String profileQuestion(ProfileField field) =>
      '$profileDetails/${field.name}';

  /// Developer tooling, never in a release build.

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

  /// The paywall the app shows by itself at [moment].
  static String paywallAt(PaywallMoment moment) =>
      '$paywall?moment=${moment.name}';
}

/// Whether [location] is past the start (splash, retry, onboarding and the
/// program suggested after it), where the app leads the way and a
/// notification tap waits.
bool isPastStart(String location) =>
    location.isNotEmpty &&
    location != Routes.splash &&
    location != Routes.startFailed &&
    location != Routes.verifyEmail &&
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
/// user's profile resolve, a retry screen when the guest sign-in failed, the
/// verification page while an email account is not verified, and
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
    // retried guest start), hence the uid in the key, and so can the same
    // user's after a pending spell (signed in again after an email change
    // ended the session), hence distinct before the filter.
    refreshListenable: Listenable.merge([
      deletionUnderway,
      _StreamListenable(
        auth.stream
            .map(
              (state) => (
                type: state.runtimeType,
                unverified: switch (state) {
                  Authenticated(:final user) => user.needsEmailVerification,
                  _ => false,
                },
              ),
            )
            .distinct(),
      ),
      _StreamListenable(
        profile.stream
            .map((state) => (uid: state.uid, gate: _profileGate(state)))
            .distinct()
            .where((key) => key.gate != _ProfileGate.pending),
      ),
    ]),
    redirect: (context, state) {
      if (deletionUnderway?.value ?? false) return null;
      final location = state.matchedLocation;
      final atGate =
          location == Routes.splash ||
          location == Routes.startFailed ||
          location == Routes.verifyEmail;
      final atOnboarding =
          location == Routes.onboarding ||
          location.startsWith('${Routes.onboarding}/');
      return switch (auth.state) {
        AuthUnknown() => Routes.splash,
        Unauthenticated() => Routes.startFailed,
        // Nothing else opens until the address is verified.
        Authenticated(:final user) when user.needsEmailVerification =>
          location == Routes.verifyEmail ? null : Routes.verifyEmail,
        Authenticated(:final user) => switch (_profileGate(
          profile.state,
          uid: user.id,
        )) {
          // Wait for the first snapshot, so a returning user never sees
          // onboarding flash. Someone already in the app stays where they are.
          _ProfileGate.pending =>
            location == Routes.startFailed || location == Routes.verifyEmail
                ? Routes.splash
                : null,
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
      _route(
        'splash',
        path: Routes.splash,
        builder: (_, _) => const AppSplash(),
      ),
      _route(
        'start_failed',
        path: Routes.startFailed,
        builder: (_, _) => AppStartFailed(onRetry: auth.retryGuestSignIn),
      ),
      _route(
        'verify_email',
        path: Routes.verifyEmail,
        builder: (context, _) => EmailVerificationPage(
          strings: localizedAuthStrings(AppLocalizations.of(context)),
        ),
      ),
      _route(
        'onboarding',
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingPage(),
        routes: [
          _route(
            'sign_in',
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
      _route(
        'after_onboarding',
        path: Routes.afterOnboarding,
        builder: (_, _) => OnboardingPermissionsPage(
          next: ProgramSuggestionPage(
            beforeLeaving: (context) =>
                context.paywallMoment(PaywallMoment.onboarding),
          ),
        ),
      ),
      _route(
        'workout',
        path: Routes.workout,
        pageBuilder: (_, state) =>
            RisingPage(key: state.pageKey, child: const WorkoutPage()),
        routes: [
          ..._pickerRoutes(limit: WorkoutLimits.maxExercises, root: root),
          _workoutExercise(Routes.workoutExercise, ExerciseViewSource.workout),
          _feedback(FeedbackSource.rating),
        ],
      ),
      _route(
        'generator',
        path: Routes.programGenerator,
        pageBuilder: (_, state) => _pushed(state, const GeneratorPage()),
        routes: [
          _route(
            'generator_preview',
            path: 'preview',
            redirect: (_, state) => state.extra is GeneratorAnswers
                ? null
                : Routes.programGenerator,
            pageBuilder: (_, state) => _pushed(
              state,
              GeneratorPreviewPage(answers: state.extra! as GeneratorAnswers),
            ),
          ),
          ..._pickerRoutes(limit: ProgramLimits.maxItemsPerDay, root: root),
        ],
      ),
      _route(
        'paywall',
        path: Routes.paywall,
        pageBuilder: (context, state) {
          final moment = PaywallMoment.values
              .asNameMap()[state.uri.queryParameters['moment']];
          final page = PaywallPage(moment: moment);
          // One the offering decides may be the hard paywall, so it is full
          // screen and no drag closes it; only its close button does, when
          // it has one.
          return moment?.offeringDecides ?? false
              ? AppPage(key: state.pageKey, fullscreenDialog: true, child: page)
              : _overFlow(context, state, page);
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => RepositoryProvider.value(
          value: unsavedChanges,
          child: AppShell(shell: shell),
        ),
        branches: [
          _tab(
            'today',
            Routes.today,
            const TodayPage(),
            routes: [
              ..._pickerRoutes(limit: WorkoutLimits.maxExercises, root: root),
              _workoutExercise(
                Routes.todayExercise,
                ExerciseViewSource.history,
              ),
              _route(
                'workout_detail',
                path: 'workouts/:id',
                pageBuilder: (_, state) => _pushed(
                  state,
                  WorkoutDetailPage(
                    id: state.pathParameters['id']!,
                    routes: Routes.todayEditing,
                  ),
                ),
                routes: [
                  _route(
                    'workout_edit',
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
              _route(
                'calculators',
                path: 'calculators',
                pageBuilder: (_, state) =>
                    _pushed(state, const CalculatorsPage()),
                routes: [
                  _page('calories', 'calories', const CaloriesPage()),
                  _page('body_fat', 'body-fat', const BodyFatPage()),
                  _page('one_rep_max', 'one-rep-max', const OneRepMaxPage()),
                  _route(
                    'plates',
                    path: 'plates',
                    pageBuilder: (_, state) =>
                        _pushed(state, const PlatesPage()),
                    routes: [
                      _page('bar_plates', 'bar-plates', const BarPlatesPage()),
                    ],
                  ),
                  _page('macros', 'macros', const MacrosPage()),
                  _page('body_indices', 'bmi-ffmi', const BodyIndicesPage()),
                ],
              ),
              _feedback(FeedbackSource.rating),
            ],
          ),
          _tab(
            'programs',
            Routes.programs,
            const ProgramsPage(),
            routes: [
              // Before ':id', which would match these too.
              _route(
                'program_builder',
                path: 'new',
                pageBuilder: (_, state) => _pushed(
                  state,
                  ProgramBuilderPage(
                    returns: state.uri.queryParameters['return'] == 'true',
                  ),
                ),
              ),
              ..._pickerRoutes(limit: ProgramLimits.maxItemsPerDay, root: root),
              _route(
                'catalogue',
                path: 'catalogue',
                pageBuilder: (_, state) =>
                    _pushed(state, const CataloguePage()),
                routes: [
                  _route(
                    'catalogue_detail',
                    path: ':id',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      CatalogueDetailPage(id: state.pathParameters['id']!),
                    ),
                    routes: [
                      _route(
                        'catalogue_volume',
                        path: 'volume',
                        pageBuilder: (_, state) => _pushed(
                          state,
                          CatalogueVolumePage(id: state.pathParameters['id']!),
                        ),
                      ),
                      _route(
                        'exercise_detail',
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
                            from: ExerciseViewSource.catalogue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Before ':id', which would match 'volume' too.
              _route(
                'program_volume',
                path: 'volume/:id',
                pageBuilder: (_, state) => _pushed(
                  state,
                  ProgramVolumePage(id: state.pathParameters['id']!),
                ),
              ),
              _route(
                'program_detail',
                path: ':id',
                pageBuilder: (_, state) => _pushed(
                  state,
                  ProgramDetailPage(
                    // Another program, e.g. a copy just made from this
                    // page, gets a page of its own, not this one's state.
                    key: ValueKey(state.pathParameters['id']),
                    id: state.pathParameters['id']!,
                    created: state.uri.queryParameters['created'] == 'true',
                    onboarding:
                        state.uri.queryParameters['from'] == 'onboarding',
                  ),
                ),
                routes: [
                  _route(
                    'program_builder',
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
            'exercises',
            Routes.exercises,
            const ExercisesPage(),
            routes: [
              // Before ':id', which would match these too.
              _route(
                'exercise_list',
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
              _route(
                'custom_exercise_new',
                path: 'new',
                pageBuilder: (_, state) => _pushed(
                  state,
                  CustomExerciseNewPage(
                    name: state.uri.queryParameters['name'],
                  ),
                ),
              ),
              _route(
                'program_builder',
                path: 'new-program',
                pageBuilder: (_, state) => _pushed(
                  state,
                  const ProgramBuilderPage(
                    returns: true,
                    picker: Routes.exerciseProgramPicker,
                  ),
                ),
                routes: [
                  ..._pickerRoutes(
                    limit: ProgramLimits.maxItemsPerDay,
                    root: root,
                  ),
                ],
              ),
              _route(
                'exercise_detail',
                path: ':id',
                pageBuilder: (_, state) => _pushed(
                  state,
                  ExerciseDetailPage(
                    exerciseId: state.pathParameters['id']!,
                    exerciseRoute: Routes.exercise,
                    from: ExerciseViewSource.library,
                  ),
                ),
                routes: [
                  _route(
                    'custom_exercise_edit',
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
            'progress',
            Routes.progress,
            const ProgressPage(),
            routes: [
              _route(
                'cardio',
                path: 'cardio',
                pageBuilder: (_, state) =>
                    _pushed(state, const CardioListPage()),
                routes: [
                  // Before ':id', which would match 'new' too.
                  _route(
                    'cardio_new',
                    path: 'new',
                    pageBuilder: (_, state) =>
                        _pushed(state, const CardioNewPage()),
                  ),
                  _route(
                    'cardio_session',
                    path: ':id',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      CardioSessionPage(id: state.pathParameters['id']!),
                    ),
                    routes: [
                      _route(
                        'cardio_edit',
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
              _route(
                'volume',
                path: 'volume',
                pageBuilder: (_, state) => _pushed(state, const VolumePage()),
              ),
              _route(
                'strength',
                path: Routes.strengthSegment,
                pageBuilder: (_, state) =>
                    _pushed(state, const StrengthListPage()),
                routes: [
                  _route(
                    'exercise_strength',
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
              _route(
                'calendar',
                path: 'calendar',
                pageBuilder: (_, state) => _pushed(state, const CalendarPage()),
                routes: [
                  // Before ':id', which would match these too.
                  _route(
                    'past_workout_new',
                    path: 'new',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      WorkoutEditPage(
                        plan: state.extra as PastWorkoutPlan?,
                        routes: Routes.calendarEditing,
                      ),
                    ),
                  ),
                  ..._pickerRoutes(
                    limit: WorkoutLimits.maxExercises,
                    root: root,
                  ),
                  _workoutExercise(
                    Routes.calendarExercise,
                    ExerciseViewSource.history,
                  ),
                  _route(
                    'workout_detail',
                    path: ':id',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      WorkoutDetailPage(
                        id: state.pathParameters['id']!,
                        routes: Routes.calendarEditing,
                      ),
                    ),
                    routes: [
                      _route(
                        'workout_edit',
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
              _route(
                'steps',
                path: 'steps',
                pageBuilder: (_, state) => _pushed(state, const StepsPage()),
              ),
              _route(
                'body',
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
                  _route(
                    'measurement_day_new',
                    path: 'measure',
                    pageBuilder: (_, state) =>
                        _pushed(state, const MeasurementDayNewPage()),
                  ),
                  // Right after a new measurement day is saved.
                  _route(
                    'measurement_summary',
                    path: 'summary/:id',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      MeasurementSummaryPage(id: state.pathParameters['id']!),
                    ),
                  ),
                  _route(
                    'body_entry',
                    path: ':id',
                    pageBuilder: (_, state) => _pushed(
                      state,
                      BodyEntryPage(id: state.pathParameters['id']!),
                    ),
                    routes: [
                      _route(
                        'measurement_day_edit',
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
            'profile',
            Routes.profile,
            ProfilePage(devTools: profileDevTools),
            routes: [
              _route(
                'account',
                path: 'account',
                pageBuilder: (_, state) => _pushed(state, const AccountPage()),
                routes: [
                  _route(
                    'account_auth',
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
                  _route(
                    'account_delete',
                    path: 'delete',
                    pageBuilder: (_, state) =>
                        _pushed(state, const DeleteAccountPage()),
                  ),
                ],
              ),
              _route(
                'bar_plates',
                path: 'bar-plates',
                pageBuilder: (_, state) =>
                    _pushed(state, const BarPlatesPage()),
              ),
              _feedback(FeedbackSource.profile),
              _route(
                'warmup_settings',
                path: 'warmups',
                pageBuilder: (_, state) =>
                    _pushed(state, const WarmupSettingsPage()),
              ),
              _route(
                'profile_details',
                path: 'details',
                pageBuilder: (_, state) =>
                    _pushed(state, const ProfileDetailsPage()),
                routes: [
                  _route(
                    'profile_question',
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
/// exercises, with a custom exercise created above it as a full page.
/// Adding (and leaving out) opens over the flow (close) from the [root]
/// navigator, so a picker opened inside a tab covers the tab bar too; Swap
/// and Replace are steps of their page (back), at `swap`.
List<GoRoute> _pickerRoutes({
  required int limit,
  required GlobalKey<NavigatorState> root,
}) {
  ExercisePickerPage page(GoRouterState state) {
    final query = state.uri.queryParameters;
    final max = int.tryParse(query['max'] ?? '') ?? 1;
    return ExercisePickerPage(
      max: max < 1 ? 1 : max,
      limit: limit,
      multiple: query['multiple'] == 'true',
      form: ExercisePickerForm.byName(query['form']),
      exerciseId: query['exercise'],
      logged: int.tryParse(query['logged'] ?? '') ?? 0,
      warmups: int.tryParse(query['warmups'] ?? '') ?? 0,
    );
  }

  GoRoute create({GlobalKey<NavigatorState>? over}) => _route(
    'custom_exercise_new',
    path: 'new',
    parentNavigatorKey: over,
    pageBuilder: (_, state) => _pushed(
      state,
      CustomExerciseNewPage(name: state.uri.queryParameters['name']),
    ),
  );

  return [
    _route(
      'exercise_picker',
      path: 'pick',
      parentNavigatorKey: root,
      pageBuilder: (context, state) => _overFlow(context, state, page(state)),
      routes: [create(over: root)],
    ),
    _route(
      'exercise_picker',
      path: pickStepPath,
      pageBuilder: (_, state) => _pushed(state, page(state)),
      routes: [create()],
    ),
  ];
}

/// An exercise's detail page pushed above a workout (in progress or being
/// edited, as [from] says), so going back returns to it; [exerciseRoute] is
/// where it opens other exercises.
GoRoute _workoutExercise(
  String Function(String id) exerciseRoute,
  ExerciseViewSource from,
) => _route(
  'exercise_detail',
  path: 'exercises/:exerciseId',
  pageBuilder: (_, state) => _pushed(
    state,
    ExerciseDetailPage(
      exerciseId: state.pathParameters['exerciseId']!,
      exerciseRoute: exerciseRoute,
      from: from,
    ),
  ),
);

GoRoute _feedback(FeedbackSource source) => _route(
  'feedback',
  path: 'feedback',
  pageBuilder: (_, state) => _pushed(state, FeedbackPage(source: source)),
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

GoRoute _page(String screen, String path, Widget page) =>
    _route(screen, path: path, pageBuilder: (_, state) => _pushed(state, page));

StatefulShellBranch _tab(
  String screen,
  String path,
  Widget page, {
  List<RouteBase> routes = const [],
}) => StatefulShellBranch(
  routes: [_route(screen, path: path, builder: (_, _) => page, routes: routes)],
);

/// The screen name each route shows, for analytics' screen views.
final _screens = Expando<String>('screen');

/// A [GoRoute] showing [screen].
GoRoute _route(
  String screen, {
  required String path,
  GoRouterWidgetBuilder? builder,
  GoRouterPageBuilder? pageBuilder,
  GlobalKey<NavigatorState>? parentNavigatorKey,
  GoRouterRedirect? redirect,
  List<RouteBase> routes = const [],
}) {
  final route = GoRoute(
    path: path,
    builder: builder,
    pageBuilder: pageBuilder,
    parentNavigatorKey: parentNavigatorKey,
    redirect: redirect,
    routes: routes,
  );
  _screens[route] = screen;
  return route;
}

/// The screen in front in [stack]: the name of its top page's route and
/// that page's key, which tells another page of the same screen apart.
/// Null when the route has no name. A dialog or sheet the app opens
/// without a route is not part of the stack.
({String name, LocalKey page})? screenInFront(RouteMatchList stack) {
  RouteMatch? top;
  void visit(List<RouteMatchBase> matches) {
    switch (matches.lastOrNull) {
      case final ShellRouteMatch shell:
        visit(shell.matches);
      case final RouteMatch match:
        top = match;
      case _:
    }
  }

  visit(stack.matches);
  final match = top;
  final name = match == null ? null : _screens[match.route];
  if (match == null || name == null) return null;
  return (name: name, page: match.pageKey);
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
