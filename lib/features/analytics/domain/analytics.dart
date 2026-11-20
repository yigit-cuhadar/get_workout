import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';

import '../../cardio/domain/cardio_type.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';
import '../../subscription/domain/paywall_layout.dart';
import '../../subscription/domain/paywall_moment.dart';
import '../../workout/domain/exercise_stats.dart';

/// The onboarding steps in the order they show, [index] their position.
enum OnboardingStep {
  welcome('welcome'),
  goal('goal'),
  level('level'),
  days('days'),
  equipment('equipment'),
  sex('sex'),
  birthYear('birth_year'),
  height('height'),
  weight('weight'),
  targetWeight('target_weight'),
  permissions('permissions'),
  program('program');

  const OnboardingStep(this.code);
  final String code;
}

/// How a workout came to be: a program day, an empty one, or one logged
/// afterwards.
enum WorkoutSource { program, free, past }

/// Where an exercise's page was opened: the Exercises tab, a ready-made
/// program, the workout in progress, or a stored workout being edited.
enum ExerciseViewSource { library, catalogue, workout, history }

enum Calculator {
  calories('calories'),
  bodyFat('body_fat'),
  oneRepMax('one_rep_max'),
  plates('plates'),
  macros('macros'),
  bodyIndices('body_indices');

  const Calculator(this.code);
  final String code;
}

/// What a free user tapped that needs Premium.
enum PremiumFeature {
  generator('generator'),
  premiumProgram('premium_program'),
  bodyHistory('body_history'),
  bodySeries('body_series'),
  bodyRange('body_range'),
  strengthRange('strength_range');

  const PremiumFeature(this.code);
  final String code;
}

/// The user property `premium`.
enum PremiumTier { free, trial, premium }

/// What a tapped notification was about.
enum NotificationKind {
  workout('workout'),
  measurement('measurement'),
  announcement('announcement'),
  activeWorkout('active_workout');

  const NotificationKind(this.code);
  final String code;
}

/// The app's analytics: every event, user property and screen of SPEC's
/// event plan, with its name and parameters, in one place. Never fails;
/// drops everything while collection is off ([Telemetry]).
class Analytics {
  const Analytics(this._telemetry);
  final Telemetry _telemetry;

  Future<void> screen(String name) => _telemetry.logScreen(name);

  // User properties.

  Future<void> level(Level? level) => _property('level', level?.code);

  Future<void> goal(Goal? goal) => _property('goal', goal?.code);

  Future<void> daysPerWeek(int? days) =>
      _property('days_per_week', days?.toString());

  Future<void> premium(PremiumTier tier) => _property('premium', tier.name);

  Future<void> acquisition({required bool searchAds}) =>
      _property('acquisition', searchAds ? 'apple_search_ads' : 'organic');

  /// A guest without [method], else how the account signs in.
  Future<void> account(SignInMethod? method) =>
      _property('account', method?.name ?? 'guest');

  Future<void> hasProgram(bool hasProgram) =>
      _property('has_program', '$hasProgram');

  // Onboarding.

  Future<void> onboardingStart() => _log('onboarding_start');

  Future<void> onboardingStep(OnboardingStep step) =>
      _log('onboarding_step', {'step': step.code, 'index': step.index});

  /// [programId]: the ready-made program saved from the suggestion.
  Future<void> onboardingComplete({String? programId}) =>
      _log('onboarding_complete', {'program_id': ?programId});

  // Account.

  Future<void> signUp(SignInMethod method) =>
      _log('sign_up', {'method': method.name});

  Future<void> login(SignInMethod method) =>
      _log('login', {'method': method.name});

  Future<void> signOut() => _log('sign_out');

  Future<void> accountDelete() => _log('account_delete');

  // Programs.

  /// [program] started, saved from onboarding's suggestion when
  /// [onboarding]; a ready-made one's id is the catalogue program's.
  Future<void> programStart(Program program, {required bool onboarding}) =>
      _log('program_start', {
        'source': onboarding
            ? 'onboarding'
            : switch (program.origin) {
                ProgramOrigin.catalog => 'catalog',
                ProgramOrigin.generated => 'generator',
                ProgramOrigin.own => 'custom',
              },
        if (program.origin == ProgramOrigin.catalog)
          'program_id': ?program.sourceId,
        'premium': '${program.premium}',
      });

  Future<void> programGenerate({required Goal goal, required int days}) =>
      _log('program_generate', {'goal': goal.code, 'days': days});

  Future<void> programCreate() => _log('program_create');

  Future<void> programEdit() => _log('program_edit');

  // Workout.

  Future<void> workoutStart(WorkoutSource source) =>
      _log('workout_start', {'source': source.name});

  /// [workoutCount]: the user's workouts with this one; null when it
  /// could not be counted.
  Future<void> workoutComplete({
    required WorkoutSource source,
    required Duration duration,
    required int exercises,
    required int sets,
    required int records,
    int? workoutCount,
  }) => _log('workout_complete', {
    'source': source.name,
    'duration_min': duration.inMinutes,
    'exercises': exercises,
    'sets': sets,
    'records': records,
    'workout_count': ?workoutCount,
  });

  Future<void> firstWorkoutComplete() => _log('first_workout_complete');

  Future<void> workoutDiscard() => _log('workout_discard');

  Future<void> personalRecord(String exerciseId, RecordKind kind) =>
      _log('personal_record', {'exercise_id': exerciseId, 'kind': kind.code});

  Future<void> restSkip() => _log('rest_skip');

  // Library and model.

  Future<void> muscleSelect(Muscle muscle) =>
      _log('muscle_select', {'muscle': muscle.code});

  Future<void> exerciseView(String exerciseId, ExerciseViewSource from) =>
      _log('exercise_view', {'exercise_id': exerciseId, 'from': from.name});

  Future<void> exerciseSearch() => _log('exercise_search');

  Future<void> customExerciseCreate() => _log('custom_exercise_create');

  // Body and progress.

  Future<void> weightLog() => _log('weight_log');

  Future<void> measurementDaySave({required int photos}) =>
      _log('measurement_day_save', {'photos': photos});

  Future<void> cardioLog(CardioType kind) =>
      _log('cardio_log', {'kind': kind.code});

  Future<void> calculatorUse(Calculator calculator) =>
      _log('calculator_use', {'calculator': calculator.code});

  Future<void> stepsConnect({required bool granted}) =>
      _log('steps_connect', {'granted': '$granted'});

  // Monetization.

  /// The A/B test's activation event: the paywall showed its plans, those
  /// of the store's [offering] (null: the store named none).
  Future<void> paywallView({
    required PaywallLayout layout,
    required PaywallMoment? moment,
    required String? offering,
  }) => _log('paywall_view', {
    'layout': layout.code,
    'moment': _moment(moment),
    'offering': ?offering,
  });

  Future<void> paywallClose(PaywallMoment? moment) =>
      _log('paywall_close', {'moment': _moment(moment)});

  /// The A/B test's goal: a plan bought, or its trial started, on the
  /// paywall. The plan is its period, the same on both stores (their
  /// product ids differ).
  Future<void> paywallPurchase({
    required PlanPeriod plan,
    required PaywallLayout layout,
    required PaywallMoment? moment,
  }) => _log('paywall_purchase', {
    'plan': plan.name,
    'layout': layout.code,
    'moment': _moment(moment),
  });

  Future<void> restore({required bool premium}) =>
      _log('restore', {'premium': '$premium'});

  Future<void> premiumLockTap(PremiumFeature feature) =>
      _log('premium_lock_tap', {'feature': feature.code});

  Future<void> manageSubscription() => _log('manage_subscription');

  // Engagement.

  Future<void> notificationOpen(NotificationKind kind) =>
      _log('notification_open', {'kind': kind.code});

  Future<void> reviewPrompt() => _log('review_prompt');

  Future<void> feedbackSend() => _log('feedback_send');

  /// A paywall the user opened has no moment.
  static String _moment(PaywallMoment? moment) => switch (moment) {
    null => 'user',
    PaywallMoment.onboarding => 'onboarding',
    PaywallMoment.firstWorkout => 'first_workout',
    PaywallMoment.appOpen => 'app_open',
  };

  Future<void> _log(String name, [Map<String, Object> parameters = const {}]) =>
      _telemetry.logEvent(name, parameters);

  Future<void> _property(String name, String? value) =>
      _telemetry.setUserProperty(name, value);
}
