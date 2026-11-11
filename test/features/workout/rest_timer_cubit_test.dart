import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/workout/domain/rest.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/features/workout/presentation/rest_timer_cubit.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockWorkoutCubit extends MockCubit<ActiveWorkoutState>
    implements ActiveWorkoutCubit {}

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class MockNotifications extends Mock implements Notifications {}

void main() {
  final start = DateTime(2026, 11, 11, 18);
  final squats = workout('w1', [
    exercise('squat', [lift(100, 5), const WorkoutSet()]),
  ]);
  const first = (exercise: 0, set: 0);
  const id = RestTimerCubit.notificationId;
  const base = UserSettings(
    weightUnit: WeightUnit.kg,
    lengthUnit: LengthUnit.cm,
  );

  late MockWorkoutCubit workoutCubit;
  late StreamController<ActiveWorkoutState> workoutStates;
  late ActiveWorkoutState workoutState;
  late MockSettingsCubit settings;
  late SettingsState settingsState;
  late MockNotifications notifications;
  late NotificationPermission permission;
  late bool exact;

  setUpAll(() {
    registerFallbackValue(base);
    registerFallbackValue(DateTime(2000));
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
    when(() => settings.update(any())).thenAnswer((call) async {
      settingsState = SettingsState(
        call.positionalArguments.single as UserSettings,
      );
    });

    notifications = MockNotifications();
    permission = NotificationPermission.granted;
    exact = true;
    when(() => notifications.cancel(any()))
        .thenAnswer((_) async => const Ok(null));
    when(
      () => notifications.scheduleAt(
        any(),
        any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async => const Ok(null));
    when(notifications.status).thenAnswer((_) async => Ok(permission));
    when(notifications.request).thenAnswer((_) async => Ok(permission));
    when(notifications.canScheduleExact).thenAnswer((_) async => Ok(exact));
    when(notifications.requestExact).thenAnswer((_) async => const Ok(true));
  });

  tearDown(() => workoutStates.close());

  void setNotify(bool? notify) => settingsState = SettingsState(
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
          notifications: Future.value(notifications),
          text: (workout, next) => (
            title: 'Rest over',
            body: next == null
                ? 'Done'
                : '${workout.exercises[next.exercise].name} ${next.set + 1}',
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

  void verifyScheduled(DateTime at, {String body = 'squat 2'}) => verify(
    () => notifications.scheduleAt(id, at, title: 'Rest over', body: body),
  ).called(1);

  void verifyNothingScheduled() => verifyNever(
    () => notifications.scheduleAt(
      any(),
      any(),
      title: any(named: 'title'),
      body: any(named: 'body'),
    ),
  );

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
        verify(() => notifications.cancel(id)).called(1);
        verifyNothingScheduled();
      });
    });
  });

  group('notification', () {
    final end = start.add(const Duration(seconds: 90));

    test('any one left from before is cancelled at start', () {
      run((async, cubit) {
        verify(() => notifications.cancel(id)).called(1);
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
        verify(() => notifications.cancel(id)).called(1);
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
          () => notifications.cancel(id),
          () => notifications.scheduleAt(
            id,
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
          verify(() => notifications.cancel(id)).called(1);
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
        setNotify(notify);
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
        () => notifications.scheduleAt(
          any(),
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
  });

  group('permission', () {
    final end = start.add(const Duration(seconds: 90));

    test('is asked the first time a rest starts, once', () {
      setNotify(null);
      run((async, cubit) {
        emitRest(Rest(endsAt: end, after: first));
        expect(cubit.state.askNotify, isTrue);
        unawaited(cubit.answerNotify(allow: false));
        async.flushMicrotasks();
        expect(cubit.state.askNotify, isFalse);
        expect(settingsState.settings.restTimer.notify, isFalse);
        verifyNever(notifications.request);
        emitRest(Rest(endsAt: end.add(restExtension), after: first));
        expect(cubit.state.askNotify, isFalse);
      });
    });

    test('is not asked for a rest kept from before the start', () {
      setNotify(null);
      workoutState = const ActiveWorkoutState(status: WorkoutStatus.loading);
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        expect(cubit.state.askNotify, isFalse);
      });
    });

    test('a yes asks the device, then for exact alarms', () {
      setNotify(null);
      exact = false;
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        unawaited(cubit.answerNotify(allow: true));
        async.flushMicrotasks();
        verify(notifications.request).called(1);
        verify(notifications.requestExact).called(1);
        expect(settingsState.settings.restTimer.notify, isTrue);
      });
    });

    test('exact alarms are not asked for when allowed', () {
      run((async, cubit) {
        unawaited(cubit.setNotify(true));
        async.flushMicrotasks();
        verifyNever(notifications.requestExact);
      });
    });

    test('a yes the device refuses is stored as a no', () {
      setNotify(null);
      permission = NotificationPermission.denied;
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        unawaited(cubit.answerNotify(allow: true));
        async.flushMicrotasks();
        verifyNever(notifications.requestExact);
        expect(settingsState.settings.restTimer.notify, isFalse);
      });
    });

    test('a stored yes is checked against the device once', () {
      permission = NotificationPermission.denied;
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        async.flushMicrotasks();
        verify(notifications.request).called(1);
        expect(settingsState.settings.restTimer.notify, isFalse);
        emitRest(Rest(endsAt: end.add(restExtension)));
        async.flushMicrotasks();
        verifyNever(notifications.request);
      });
    });

    test('a stored yes the device allows asks nothing', () {
      run((async, cubit) {
        emitRest(Rest(endsAt: end));
        async.flushMicrotasks();
        verify(notifications.status).called(1);
        verifyNever(notifications.request);
        expect(cubit.state.askNotify, isFalse);
      });
    });

    test('turning it off in the settings stores it', () {
      run((async, cubit) {
        unawaited(cubit.setNotify(false));
        async.flushMicrotasks();
        expect(settingsState.settings.restTimer.notify, isFalse);
      });
    });
  });
}
