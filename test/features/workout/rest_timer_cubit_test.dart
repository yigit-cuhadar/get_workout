import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/workout/domain/rest.dart';
import 'package:get_workout/features/workout/domain/rest_lock_screen.dart';
import 'package:get_workout/features/workout/domain/rest_notifications.dart';
import 'package:get_workout/features/workout/domain/rest_usecases.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/features/workout/presentation/rest_timer_cubit.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockWorkoutCubit extends MockCubit<ActiveWorkoutState>
    implements ActiveWorkoutCubit {}

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class MockRestNotifications extends Mock implements RestNotifications {}

class MockRestLockScreen extends Mock implements RestLockScreen {}

void main() {
  final start = DateTime(2026, 11, 11, 18);
  final squats = workout('w1', [
    exercise('squat', [lift(100, 5), const WorkoutSet()]),
  ]);
  const first = (exercise: 0, set: 0);
  const base = UserSettings(
    weightUnit: WeightUnit.kg,
    lengthUnit: LengthUnit.cm,
  );

  late MockWorkoutCubit workoutCubit;
  late StreamController<ActiveWorkoutState> workoutStates;
  late ActiveWorkoutState workoutState;
  late MockSettingsCubit settings;
  late SettingsState settingsState;
  late StreamController<SettingsState> settingsStates;
  late MockRestNotifications notifications;
  late MockRestLockScreen lockScreen;

  /// What this device says: whether it lets the app notify, what a request
  /// answers, and whether the user was asked here.
  late bool allowed;
  late bool requestGrants;
  late bool askedHere;

  setUpAll(() {
    registerFallbackValue(base);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(
      RestCountdown(endsAt: DateTime(2000), title: '', over: ''),
    );
  });

  setUp(() {
    workoutCubit = MockWorkoutCubit();
    workoutStates = StreamController.broadcast(sync: true);
    workoutState = ActiveWorkoutState(
      status: WorkoutStatus.active,
      workout: squats,
    );
    when(() => workoutCubit.state).thenAnswer((_) => workoutState);
    when(() => workoutCubit.stream).thenAnswer((_) => workoutStates.stream);

    settings = MockSettingsCubit();
    settingsState = SettingsState(
      base.copyWith(restTimer: const RestTimerSettings(notify: true)),
    );
    when(() => settings.state).thenAnswer((_) => settingsState);
    settingsStates = StreamController.broadcast(sync: true);
    when(() => settings.stream).thenAnswer((_) => settingsStates.stream);
    when(() => settings.update(any())).thenAnswer((call) async {
      settingsState = SettingsState(
        call.positionalArguments.single as UserSettings,
      );
    });

    lockScreen = MockRestLockScreen();
    when(() => lockScreen.show(any())).thenAnswer((_) async => const Ok(null));
    when(lockScreen.clear).thenAnswer((_) async => const Ok(null));

    notifications = MockRestNotifications();
    allowed = true;
    requestGrants = true;
    askedHere = true;
    when(notifications.cancel).thenAnswer((_) async => const Ok(null));
    when(
      () => notifications.schedule(
        any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async => const Ok(null));
    when(notifications.allowed).thenAnswer((_) async => Ok(allowed));
    when(notifications.request).thenAnswer((_) async {
      allowed = requestGrants;
      return Ok(requestGrants);
    });
    when(notifications.askedHere).thenAnswer((_) async => Ok(askedHere));
    when(notifications.markAskedHere).thenAnswer((_) async {
      askedHere = true;
      return const Ok(null);
    });
  });

  tearDown(() async {
    await workoutStates.close();
    await settingsStates.close();
  });

  bool? wish() => settingsState.settings.restTimer.notify;

  void setWish(bool? notify) => settingsState = SettingsState(
    base.copyWith(restTimer: RestTimerSettings(notify: notify)),
  );

  void emitWorkout(ActiveWorkoutState state) {
    workoutState = state;
    workoutStates.add(state);
  }

  void emitRest(Rest? rest) => emitWorkout(
    ActiveWorkoutState(
      status: WorkoutStatus.active,
      workout: squats,
      rest: rest,
    ),
  );

  /// Runs [body] with a cubit on a fake clock starting at [start].
  void run(void Function(FakeAsync async, RestTimerCubit cubit) body) =>
      fakeAsync((async) {
        final cubit = RestTimerCubit(
          workout: workoutCubit,
          settings: settings,
          shouldAsk: ShouldAskRestNotifications(notifications),
          allow: AllowRestNotifications(notifications),
          decline: DeclineRestNotifications(notifications),
          schedule: ScheduleRestNotification(notifications),
          cancel: CancelRestNotification(notifications),
          text: (workout, next) => (
            title: 'Rest over',
            body: next == null
                ? 'Done'
                : '${workout.exercises[next.exercise].name} ${next.set + 1}',
          ),
          showOnLockScreen: ShowRestOnLockScreen(lockScreen),
          clearLockScreen: ClearRestFromLockScreen(lockScreen),
          lockScreenText: (workout, next) => (
            title: 'Rest',
            detail: next == null
                ? null
                : '${workout.exercises[next.exercise].name} ${next.set + 1}',
            over: 'Over',
          ),
          clock: async.getClock(start).now,
        );
        async.flushMicrotasks();
        body(async, cubit);
        unawaited(cubit.close());
        async.flushMicrotasks();
      });

  RestTimerState running(int seconds) =>
      RestTimerState(phase: RestPhase.running, remainingS: seconds);

  void verifyScheduled(DateTime at, {String body = 'squat 2'}) =>
      verify(() => notifications.schedule(at, title: 'Rest over', body: body))
          .called(1);

  void verifyNothingScheduled() => verifyNever(
    () => notifications.schedule(
      any(),
      title: any(named: 'title'),
      body: any(named: 'body'),
    ),
  );

  /// Makes the next schedule wait for the returned completer.
  Completer<Result<void>> delaySchedule() {
    final done = Completer<Result<void>>();
    when(
      () => notifications.schedule(
        any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) => done.future);
    return done;
  }

  group('countdown', () {
    test('counts down to the end, says it is over, then hides', () {
      run((async, cubit) {
        emitRest(
          Rest(endsAt: start.add(const Duration(seconds: 90)), after: first),
        );
        expect(cubit.state, running(90));
        async.elapse(const Duration(milliseconds: 1));
        expect(cubit.state, running(90));
        async.elapse(const Duration(seconds: 1));
        expect(cubit.state, running(89));
        async.elapse(const Duration(seconds: 89));
        expect(cubit.state.phase, RestPhase.over);
        async.elapse(RestTimerCubit.overFor);
        expect(cubit.state, const RestTimerState());
      });
    });

    test('+15 s moves the end', () {
      run((async, cubit) {
        final end = start.add(const Duration(seconds: 60));
        emitRest(Rest(endsAt: end, after: first));
        async.elapse(const Duration(seconds: 10));
        emitRest(Rest(endsAt: end.add(restExtension), after: first));
        expect(cubit.state, running(65));
      });
    });

    test('skip ends it at once, without "over"', () {
      run((async, cubit) {
        emitRest(Rest(endsAt: start.add(const Duration(seconds: 60))));
        emitRest(null);
        expect(cubit.state, const RestTimerState());
      });
    });

    test('a new rest after "over" counts again', () {
      run((async, cubit) {
        emitRest(Rest(endsAt: start.add(const Duration(seconds: 5))));
        async.elapse(const Duration(seconds: 5));
        expect(cubit.state.phase, RestPhase.over);
        emitRest(Rest(endsAt: start.add(const Duration(seconds: 65))));
        expect(cubit.state, running(60));
        async.elapse(RestTimerCubit.overFor);
        expect(cubit.state, running(57));
      });
    });

    test('a rest kept from before a restart runs on from its end time', () {
      workoutState = ActiveWorkoutState(
        status: WorkoutStatus.active,
        workout: squats,
        rest: Rest(endsAt: start.add(const Duration(seconds: 40))),
      );
      run((async, cubit) {
        expect(cubit.state, running(40));
      });
    });

    test('one that ended before the restart shows nothing', () {
      workoutState = ActiveWorkoutState(
        status: WorkoutStatus.active,
        workout: squats,
        rest: Rest(endsAt: start.subtract(const Duration(seconds: 1))),
      );
      run((async, cubit) {
        expect(cubit.state, const RestTimerState());
        async.elapse(RestTimerCubit.overFor);
        expect(cubit.state, const RestTimerState());
      });
    });

    test('one ending beyond the cap (clock set back) shows nothing', () {
      workoutState = ActiveWorkoutState(
        status: WorkoutStatus.active,
        workout: squats,
        rest: Rest(
          endsAt: start.add(maxRestAhead).add(const Duration(seconds: 1)),
        ),
      );
      run((async, cubit) {
        expect(cubit.state, const RestTimerState());
        cubit.hidden();
        async.flushMicrotasks();
        verifyNothingScheduled();
      });
    });

    test('one that ended in the background ends without "over"', () {
      run((async, cubit) {
        emitRest(Rest(endsAt: start.add(const Duration(seconds: 30))));
        cubit.hidden();
        // A suspended app's timers do not run; the clock does.
        async.elapse(const Duration(minutes: 2));
        cubit.shown();
        expect(cubit.state, const RestTimerState());
      });
    });

    test('another user\'s rest is dropped with their workout', () {
      run((async, cubit) {
        emitRest(Rest(endsAt: start.add(const Duration(seconds: 60))));
        cubit.hidden();
        async.flushMicrotasks();
        clearInteractions(notifications);
        emitWorkout(const ActiveWorkoutState());
        async.flushMicrotasks();
        expect(cubit.state, const RestTimerState());
        verify(notifications.cancel).called(1);
        verifyNothingScheduled();
      });
    });
  });

  group('notification', () {
    final end = start.add(const Duration(seconds: 90));

    test('any one left from before is cancelled at start', () {
      run((async, cubit) {
        verify(notifications.cancel).called(1);
      });
    });

    test('is scheduled for the end only while the app is hidden', () {
      run((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        async.flushMicrotasks();
        verifyNothingScheduled();
        cubit.hidden();
        async.flushMicrotasks();
        verifyScheduled(end);
        clearInteractions(notifications);
        cubit.shown();
        async.flushMicrotasks();
        verify(notifications.cancel).called(1);
      });
    });

    test('names the next set, or none left', () {
      run((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        cubit.hidden();
        async.flushMicrotasks();
        verifyScheduled(end);
        cubit.shown();
        emitWorkout(
          ActiveWorkoutState(
            status: WorkoutStatus.active,
            workout: workout('w1', [
              exercise('squat', [lift(100, 5)]),
            ]),
            rest: Rest(endsAt: end, after: first),
          ),
        );
        cubit.hidden();
        async.flushMicrotasks();
        verifyScheduled(end, body: 'Done');
      });
    });

    test('a change while hidden cancels and schedules again', () {
      run((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        cubit.hidden();
        async.flushMicrotasks();
        clearInteractions(notifications);
        final later = end.add(restExtension);
        emitRest(Rest(endsAt: later, after: first));
        async.flushMicrotasks();
        verifyInOrder([
          notifications.cancel,
          () => notifications.schedule(
            later,
            title: any(named: 'title'),
            body: any(named: 'body'),
          ),
        ]);
      });
    });

    test('skip, untick, finish and discard cancel it', () {
      run((async, cubit) {
        for (final ended in [
          ActiveWorkoutState(status: WorkoutStatus.active, workout: squats),
          ActiveWorkoutState(status: WorkoutStatus.finished, workout: squats),
          const ActiveWorkoutState(status: WorkoutStatus.none),
        ]) {
          emitRest(Rest(endsAt: end, after: first));
          cubit.hidden();
          async.flushMicrotasks();
          clearInteractions(notifications);
          emitWorkout(ended);
          async.flushMicrotasks();
          verify(notifications.cancel).called(1);
          verifyNothingScheduled();
          cubit.shown();
        }
      });
    });

    test('no notification once the rest is over', () {
      run((async, cubit) {
        emitRest(Rest(endsAt: start.add(const Duration(seconds: 5))));
        async.elapse(const Duration(seconds: 5));
        cubit.hidden();
        async.flushMicrotasks();
        verifyNothingScheduled();
      });
    });

    test('none unless the user said yes', () {
      for (final notify in [null, false]) {
        setWish(notify);
        run((async, cubit) {
          emitRest(Rest(endsAt: end));
          cubit.hidden();
          async.flushMicrotasks();
          verifyNothingScheduled();
        });
      }
    });

    test('a failure to schedule is only logged', () {
      when(
        () => notifications.schedule(
          any(),
          title: any(named: 'title'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => const Err(UnknownFailure('no')));
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        cubit.hidden();
        async.flushMicrotasks();
        expect(cubit.state, running(90));
      });
    });

    group('a schedule that lands late is cancelled', () {
      test('when the app came back meanwhile', () {
        run((async, cubit) {
          emitRest(Rest(endsAt: end));
          final done = delaySchedule();
          cubit.hidden();
          async.flushMicrotasks();
          cubit.shown();
          async.flushMicrotasks();
          clearInteractions(notifications);
          done.complete(const Ok(null));
          async.flushMicrotasks();
          verify(notifications.cancel).called(1);
        });
      });

      test('when the rest changed meanwhile', () {
        run((async, cubit) {
          emitRest(Rest(endsAt: end));
          final done = delaySchedule();
          cubit.hidden();
          async.flushMicrotasks();
          emitRest(null);
          async.flushMicrotasks();
          clearInteractions(notifications);
          done.complete(const Ok(null));
          async.flushMicrotasks();
          verify(notifications.cancel).called(1);
        });
      });

      test('when the user changed in the background meanwhile', () {
        run((async, cubit) {
          emitRest(Rest(endsAt: end));
          final done = delaySchedule();
          cubit.hidden();
          async.flushMicrotasks();
          emitWorkout(const ActiveWorkoutState());
          async.flushMicrotasks();
          clearInteractions(notifications);
          done.complete(const Ok(null));
          async.flushMicrotasks();
          verify(notifications.cancel).called(1);
        });
      });

      test('but kept when nothing changed', () {
        run((async, cubit) {
          emitRest(Rest(endsAt: end));
          final done = delaySchedule();
          cubit.hidden();
          async.flushMicrotasks();
          clearInteractions(notifications);
          done.complete(const Ok(null));
          async.flushMicrotasks();
          verifyNever(notifications.cancel);
        });
      });
    });
  });

  group('lock screen', () {
    final end = start.add(const Duration(seconds: 90));

    RestCountdown countdown(DateTime endsAt, {String? detail = 'squat 2'}) =>
        RestCountdown(
          endsAt: endsAt,
          title: 'Rest',
          detail: detail,
          over: 'Over',
        );

    void verifyShown(DateTime endsAt, {String? detail = 'squat 2'}) =>
        verify(() => lockScreen.show(countdown(endsAt, detail: detail)))
            .called(1);

    void verifyNotShown() => verifyNever(() => lockScreen.show(any()));

    /// Runs [body] once the start has cleared the lock screen.
    void runStarted(
      void Function(FakeAsync async, RestTimerCubit cubit) body,
    ) => run((async, cubit) {
      clearInteractions(lockScreen);
      body(async, cubit);
    });

    test('one left from an earlier run is cleared at start', () {
      run((async, cubit) {
        verify(lockScreen.clear).called(1);
        verifyNotShown();
      });
    });

    test('a rest kept from before a restart is shown at start', () {
      workoutState = ActiveWorkoutState(
        status: WorkoutStatus.active,
        workout: squats,
        rest: Rest(endsAt: end, after: first),
      );
      run((async, cubit) {
        verifyShown(end);
        verifyNever(lockScreen.clear);
      });
    });

    test('a started rest shows its end and the next set, once', () {
      runStarted((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        async.flushMicrotasks();
        verifyShown(end);

        async.elapse(const Duration(seconds: 30));
        verifyNotShown();
        verifyNever(lockScreen.clear);
      });
    });

    test('without a next set it shows no detail', () {
      final done = workout('w1', [
        exercise('squat', [lift(100, 5)]),
      ]);
      runStarted((async, cubit) {
        emitWorkout(
          ActiveWorkoutState(
            status: WorkoutStatus.active,
            workout: done,
            rest: Rest(endsAt: end, after: first),
          ),
        );
        async.flushMicrotasks();
        verifyShown(end, detail: null);
      });
    });

    test('+15 s and a restart on the next set replace it', () {
      runStarted((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        async.elapse(const Duration(seconds: 10));
        final extended = end.add(restExtension);
        emitRest(Rest(endsAt: extended, after: first));
        async.elapse(const Duration(seconds: 10));
        final restarted = start.add(const Duration(seconds: 110));
        emitRest(Rest(endsAt: restarted, after: first));
        async.flushMicrotasks();

        verifyInOrder([
          () => lockScreen.show(countdown(end)),
          () => lockScreen.show(countdown(extended)),
          () => lockScreen.show(countdown(restarted)),
        ]);
        verifyNever(lockScreen.clear);
      });
    });

    test('skip clears it', () {
      runStarted((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        async.flushMicrotasks();
        emitRest(null);
        async.flushMicrotasks();
        verify(lockScreen.clear).called(1);
      });
    });

    test('the end in front clears it, once', () {
      runStarted((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        async.elapse(const Duration(seconds: 89));
        verifyNever(lockScreen.clear);
        async.elapse(const Duration(seconds: 1));
        expect(cubit.state.phase, RestPhase.over);
        verify(lockScreen.clear).called(1);
        async.elapse(RestTimerCubit.overFor);
        verifyNever(lockScreen.clear);
      });
    });

    test('finishing, discarding and signing out clear it', () {
      runStarted((async, cubit) {
        for (final ended in [
          ActiveWorkoutState(status: WorkoutStatus.finished, workout: squats),
          const ActiveWorkoutState(status: WorkoutStatus.none),
          // Signed out: the user's workout is dropped.
          const ActiveWorkoutState(),
        ]) {
          emitRest(Rest(endsAt: end, after: first));
          async.flushMicrotasks();
          clearInteractions(lockScreen);
          emitWorkout(ended);
          async.flushMicrotasks();
          verify(lockScreen.clear).called(1);
          verifyNotShown();
        }
      });
    });

    test('shows nothing while the rest timer is off in the settings', () {
      settingsState = SettingsState(
        base.copyWith(restTimer: const RestTimerSettings(enabled: false)),
      );
      runStarted((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        async.elapse(const Duration(seconds: 10));
        verifyNotShown();
      });
    });

    test('turning the rest timer off clears it, on shows it again', () {
      void setEnabled(bool enabled) {
        settingsState = SettingsState(
          base.copyWith(restTimer: RestTimerSettings(enabled: enabled)),
        );
        settingsStates.add(settingsState);
      }

      runStarted((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        async.flushMicrotasks();
        verifyShown(end);

        setEnabled(false);
        async.flushMicrotasks();
        verify(lockScreen.clear).called(1);

        setEnabled(true);
        async.flushMicrotasks();
        verifyShown(end);
      });
    });

    test('the notification wish does not matter: it never alerts', () {
      setWish(false);
      runStarted((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        async.flushMicrotasks();
        verifyShown(end);
      });
    });

    test('calls run one after another, so the last one wins', () {
      runStarted((async, cubit) {
        // Made on fake time, so completing it runs on fake time.
        final showing = Completer<Result<void>>();
        when(() => lockScreen.show(any())).thenAnswer((_) => showing.future);
        emitRest(Rest(endsAt: end, after: first));
        emitRest(null);
        async.flushMicrotasks();
        verify(() => lockScreen.show(any())).called(1);
        verifyNever(lockScreen.clear);

        showing.complete(const Ok(null));
        async.flushMicrotasks();
        verify(lockScreen.clear).called(1);
      });
    });

    test('a failure is only logged, and later changes still apply', () {
      when(() => lockScreen.show(any()))
          .thenAnswer((_) async => const Err(UnknownFailure('disabled')));
      runStarted((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        async.flushMicrotasks();
        emitRest(null);
        async.flushMicrotasks();
        verify(() => lockScreen.show(any())).called(1);
        verify(lockScreen.clear).called(1);
      });
    });
  });

  group('permission', () {
    final end = start.add(const Duration(seconds: 90));

    test('is asked in the app the first time a rest starts, once', () {
      setWish(null);
      askedHere = false;
      run((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        async.flushMicrotasks();
        expect(cubit.state.askNotify, isTrue);
        verifyNever(notifications.request);
        unawaited(cubit.answerNotify(allow: false));
        async.flushMicrotasks();
        expect(cubit.state.askNotify, isFalse);
        emitRest(Rest(endsAt: end.add(restExtension), after: first));
        async.flushMicrotasks();
        expect(cubit.state.askNotify, isFalse);
      });
    });

    test('is not asked for a rest kept from before the start', () {
      setWish(null);
      askedHere = false;
      workoutState = const ActiveWorkoutState(status: WorkoutStatus.loading);
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        async.flushMicrotasks();
        expect(cubit.state.askNotify, isFalse);
      });
    });

    test('"not now" stays on this device and stores no wish', () {
      setWish(null);
      askedHere = false;
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        async.flushMicrotasks();
        unawaited(cubit.answerNotify(allow: false));
        async.flushMicrotasks();
        verify(notifications.markAskedHere).called(1);
        expect(wish(), isNull);
        verifyNever(() => settings.update(any()));
      });
      // Another device (nothing asked there) still asks.
      askedHere = false;
      workoutState = ActiveWorkoutState(
        status: WorkoutStatus.active,
        workout: squats,
      );
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        async.flushMicrotasks();
        expect(cubit.state.askNotify, isTrue);
      });
    });

    test('a yes asks the device and is stored for the user', () {
      setWish(null);
      askedHere = false;
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        async.flushMicrotasks();
        unawaited(cubit.answerNotify(allow: true));
        async.flushMicrotasks();
        verify(notifications.request).called(1);
        expect(wish(), isTrue);
      });
    });

    test('a device refusal leaves the wish, so a device that allows it '
        'still notifies', () {
      setWish(null);
      askedHere = false;
      requestGrants = false;
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        async.flushMicrotasks();
        unawaited(cubit.answerNotify(allow: true));
        async.flushMicrotasks();
        expect(wish(), isTrue);
      });
      // The other device, where it is allowed.
      allowed = true;
      workoutState = ActiveWorkoutState(
        status: WorkoutStatus.active,
        workout: squats,
      );
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        cubit.hidden();
        async.flushMicrotasks();
        verifyScheduled(end, body: 'squat 2');
      });
    });

    test('a yes from another device asks here in the app first, '
        'never the system on its own', () {
      allowed = false;
      askedHere = false;
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        async.flushMicrotasks();
        expect(cubit.state.askNotify, isTrue);
        verifyNever(notifications.request);
        unawaited(cubit.answerNotify(allow: true));
        async.flushMicrotasks();
        verify(notifications.request).called(1);
      });
    });

    test('a yes on a device that allows it asks nothing', () {
      askedHere = false;
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        async.flushMicrotasks();
        expect(cubit.state.askNotify, isFalse);
        verifyNever(notifications.request);
      });
    });

    test('a device asked before is not asked again', () {
      setWish(null);
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        async.flushMicrotasks();
        expect(cubit.state.askNotify, isFalse);
      });
    });

    test('a no is never asked about', () {
      setWish(false);
      askedHere = false;
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        async.flushMicrotasks();
        expect(cubit.state.askNotify, isFalse);
      });
    });

    test('the settings switch stores the wish and asks the device', () {
      setWish(null);
      run((async, cubit) {
        unawaited(cubit.setNotify(true));
        async.flushMicrotasks();
        verify(notifications.request).called(1);
        expect(wish(), isTrue);
        unawaited(cubit.setNotify(false));
        async.flushMicrotasks();
        expect(wish(), isFalse);
      });
    });
  });
}
