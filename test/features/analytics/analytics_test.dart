import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/features/analytics/domain/analytics.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/subscription/domain/paywall_layout.dart';
import 'package:get_workout/features/subscription/domain/paywall_moment.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';

import '../../fake_analytics.dart';

void main() {
  late RecordingTelemetry telemetry;
  late Analytics analytics;

  setUp(() {
    telemetry = RecordingTelemetry();
    analytics = Analytics(telemetry);
  });

  Future<List<Object>> logged(Future<void> Function() log) async {
    await log();
    return telemetry.logged.single;
  }

  test('onboarding steps carry their code and place', () async {
    expect(
      await logged(() => analytics.onboardingStep(OnboardingStep.welcome)),
      [
        'onboarding_step',
        {'step': 'welcome', 'index': 0},
      ],
    );
    telemetry.events.clear();
    expect(
      await logged(() => analytics.onboardingStep(OnboardingStep.birthYear)),
      [
        'onboarding_step',
        {'step': 'birth_year', 'index': 6},
      ],
    );
    telemetry.events.clear();
    expect(
      await logged(() => analytics.onboardingStep(OnboardingStep.program)),
      [
        'onboarding_step',
        {'step': 'program', 'index': 11},
      ],
    );
  });

  test('onboarding completes with the saved program or without one', () async {
    await analytics.onboardingComplete(programId: 'cat_1');
    await analytics.onboardingComplete();
    expect(telemetry.logged, [
      [
        'onboarding_complete',
        {'program_id': 'cat_1'},
      ],
      ['onboarding_complete', <String, Object>{}],
    ]);
  });

  test('sign-ups and logins name the method', () async {
    await analytics.signUp(SignInMethod.apple);
    await analytics.login(SignInMethod.email);
    expect(telemetry.logged, [
      [
        'sign_up',
        {'method': 'apple'},
      ],
      [
        'login',
        {'method': 'email'},
      ],
    ]);
  });

  group('program_start', () {
    Program program(ProgramOrigin origin, {String? sourceId}) => Program(
      id: 'p1',
      name: 'Push',
      origin: origin,
      sourceId: sourceId,
      days: const [],
      premium: true,
    );

    test('a ready-made one carries its catalogue id', () async {
      await analytics.programStart(
        program(ProgramOrigin.catalog, sourceId: 'cat_1'),
        onboarding: false,
      );
      expect(telemetry.logged.single, [
        'program_start',
        {'source': 'catalog', 'program_id': 'cat_1', 'premium': 'true'},
      ]);
    });

    test('generated and own ones carry no id; onboarding wins', () async {
      await analytics.programStart(
        program(ProgramOrigin.generated),
        onboarding: false,
      );
      await analytics.programStart(
        program(ProgramOrigin.own),
        onboarding: false,
      );
      await analytics.programStart(
        program(ProgramOrigin.catalog, sourceId: 'cat_1'),
        onboarding: true,
      );
      expect(telemetry.logged, [
        [
          'program_start',
          {'source': 'generator', 'premium': 'true'},
        ],
        [
          'program_start',
          {'source': 'custom', 'premium': 'true'},
        ],
        [
          'program_start',
          {'source': 'onboarding', 'program_id': 'cat_1', 'premium': 'true'},
        ],
      ]);
    });
  });

  test('a generation carries the goal and the days', () async {
    expect(
      await logged(
        () => analytics.programGenerate(goal: Goal.loseFat, days: 3),
      ),
      [
        'program_generate',
        {'goal': 'lose_fat', 'days': 3},
      ],
    );
  });

  test('a finished workout carries its numbers in whole minutes', () async {
    await analytics.workoutComplete(
      source: WorkoutSource.program,
      duration: const Duration(minutes: 52, seconds: 40),
      exercises: 5,
      sets: 18,
      records: 2,
      workoutCount: 7,
    );
    await analytics.workoutComplete(
      source: WorkoutSource.free,
      duration: const Duration(minutes: 3),
      exercises: 1,
      sets: 1,
      records: 0,
    );
    expect(telemetry.logged, [
      [
        'workout_complete',
        {
          'source': 'program',
          'duration_min': 52,
          'exercises': 5,
          'sets': 18,
          'records': 2,
          'workout_count': 7,
        },
      ],
      [
        'workout_complete',
        {
          'source': 'free',
          'duration_min': 3,
          'exercises': 1,
          'sets': 1,
          'records': 0,
        },
      ],
    ]);
  });

  test('content values use their codes', () async {
    await analytics.personalRecord('ex_squat', RecordKind.bestE1rm);
    await analytics.muscleSelect(Muscle.values.first);
    await analytics.exerciseView('ex_squat', ExerciseViewSource.catalogue);
    await analytics.cardioLog(CardioType.outdoorRun);
    await analytics.calculatorUse(Calculator.oneRepMax);
    await analytics.premiumLockTap(PremiumFeature.strengthRange);
    await analytics.notificationOpen(NotificationKind.activeWorkout);
    expect(telemetry.logged, [
      [
        'personal_record',
        {'exercise_id': 'ex_squat', 'kind': 'bestE1rm'},
      ],
      [
        'muscle_select',
        {'muscle': Muscle.values.first.code},
      ],
      [
        'exercise_view',
        {'exercise_id': 'ex_squat', 'from': 'catalogue'},
      ],
      [
        'cardio_log',
        {'kind': 'outdoor_run'},
      ],
      [
        'calculator_use',
        {'calculator': 'one_rep_max'},
      ],
      [
        'premium_lock_tap',
        {'feature': 'strength_range'},
      ],
      [
        'notification_open',
        {'kind': 'active_workout'},
      ],
    ]);
  });

  test('flags are strings, as Analytics takes no booleans', () async {
    await analytics.stepsConnect(granted: true);
    await analytics.restore(premium: false);
    await analytics.measurementDaySave(photos: 2);
    expect(telemetry.logged, [
      [
        'steps_connect',
        {'granted': 'true'},
      ],
      [
        'restore',
        {'premium': 'false'},
      ],
      [
        'measurement_day_save',
        {'photos': 2},
      ],
    ]);
  });

  test('paywall events keep the A/B names and name the moment', () async {
    await analytics.paywallView(
      layout: PaywallLayout.cards,
      moment: null,
      offering: null,
    );
    await analytics.paywallView(
      layout: PaywallLayout.list,
      moment: PaywallMoment.firstWorkout,
      offering: 'default',
    );
    await analytics.paywallPurchase(
      plan: PlanPeriod.yearly,
      layout: PaywallLayout.single,
      moment: PaywallMoment.appOpen,
    );
    await analytics.paywallClose(PaywallMoment.onboarding);
    expect(telemetry.logged, [
      [
        'paywall_view',
        {'layout': 'b', 'moment': 'user'},
      ],
      [
        'paywall_view',
        {'layout': 'a', 'moment': 'first_workout', 'offering': 'default'},
      ],
      [
        'paywall_purchase',
        {'plan': 'yearly', 'layout': 'c', 'moment': 'app_open'},
      ],
      [
        'paywall_close',
        {'moment': 'onboarding'},
      ],
    ]);
  });

  test('events without parameters', () async {
    for (final log in [
      analytics.onboardingStart,
      analytics.signOut,
      analytics.accountDelete,
      analytics.programCreate,
      analytics.programEdit,
      analytics.firstWorkoutComplete,
      analytics.workoutDiscard,
      analytics.restSkip,
      analytics.exerciseSearch,
      analytics.customExerciseCreate,
      analytics.weightLog,
      analytics.manageSubscription,
      analytics.reviewPrompt,
      analytics.feedbackSend,
    ]) {
      await log();
    }
    expect(telemetry.names, [
      'onboarding_start',
      'sign_out',
      'account_delete',
      'program_create',
      'program_edit',
      'first_workout_complete',
      'workout_discard',
      'rest_skip',
      'exercise_search',
      'custom_exercise_create',
      'weight_log',
      'manage_subscription',
      'review_prompt',
      'feedback_send',
    ]);
    expect(telemetry.events.every((event) => event.$2.isEmpty), isTrue);
  });

  test('user properties', () async {
    await analytics.level(Level.intermediate);
    await analytics.goal(null);
    await analytics.daysPerWeek(4);
    await analytics.premium(PremiumTier.trial);
    await analytics.acquisition(searchAds: true);
    await analytics.account(null);
    await analytics.hasProgram(false);
    await analytics.screen('program_detail');
    expect(telemetry.properties, {
      'level': 'intermediate',
      'goal': null,
      'days_per_week': '4',
      'premium': 'trial',
      'acquisition': 'apple_search_ads',
      'account': 'guest',
      'has_program': 'false',
    });
    expect(telemetry.screens, ['program_detail']);
  });
}
