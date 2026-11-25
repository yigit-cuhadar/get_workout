import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_live_activity/forge_live_activity.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_workout/features/workout/data/android_workout_lock_screen.dart';
import 'package:get_workout/features/workout/data/ios_workout_lock_screen.dart';
import 'package:get_workout/features/workout/domain/workout_lock_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockNotifications extends Mock implements Notifications {}

class MockLiveActivity extends Mock implements LiveActivity {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final startedAt = DateTime.utc(2026, 11, 11, 18);
  final rest = RestCountdown(
    startsAt: DateTime.utc(2026, 11, 11, 18, 0, 30),
    endsAt: DateTime.utc(2026, 11, 11, 18, 2),
    title: 'Rest',
    detail: 'Next: Squat, set 2',
  );
  const squat = LockScreenSet(
    exercise: 'Squat',
    position: 'Exercise 1 of 4',
    line: 'Set 2 of 3 · 80 kg × 8',
    done: [true, false, false],
  );
  final training = LockScreenWorkout(
    name: 'Legs',
    startedAt: startedAt,
    current: 'Squat · set 2 of 3',
    set: squat,
  );
  final resting = LockScreenWorkout(
    name: 'Legs',
    startedAt: startedAt,
    current: 'Squat · set 2 of 3',
    set: squat,
    rest: rest,
  );
  setUpAll(() {
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(<String, Object?>{});
  });

  group('Android', () {
    late MockNotifications notifications;
    late AndroidWorkoutLockScreen lockScreen;
    final edited = LockScreenWorkout(
      name: 'Legs',
      startedAt: startedAt,
      current: 'Squat · set 3 of 3',
    );

    setUp(() {
      notifications = MockNotifications();
      lockScreen = AndroidWorkoutLockScreen(
        Future.value(notifications),
        payload: 'open',
      );
      when(() => notifications.cancel(any()))
          .thenAnswer((_) async => const Ok(null));
      when(
        () => notifications.showCountdown(
          any(),
          endsAt: any(named: 'endsAt'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async => const Ok(null));
      when(
        () => notifications.showStopwatch(
          any(),
          since: any(named: 'since'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async => const Ok(null));
      when(
        () => notifications.scheduleStopwatch(
          any(),
          any(),
          since: any(named: 'since'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async => const Ok(null));
    });

    Future<Result<void>> showsCountdown() => notifications.showCountdown(
      2,
      endsAt: rest.endsAt,
      title: 'Rest',
      body: 'Next: Squat, set 2',
      payload: 'open',
    );

    Future<Result<void>> showsWorkout(LockScreenWorkout workout) =>
        notifications.showStopwatch(
          3,
          since: startedAt,
          title: 'Legs',
          body: workout.current,
          payload: 'open',
        );

    Future<Result<void>> schedulesWorkout() => notifications.scheduleStopwatch(
      3,
      rest.endsAt,
      since: startedAt,
      title: 'Legs',
      body: 'Squat · set 2 of 3',
      payload: 'open',
    );

    test('a rest shows its countdown, and the workout only from its '
        'end', () async {
      expect((await lockScreen.show(resting)).isOk, isTrue);

      verifyInOrder([
        showsCountdown,
        () => notifications.cancel(3),
        schedulesWorkout,
      ]);
      verifyNever(() => notifications.cancel(2));
      verifyNever(() => showsWorkout(training));
    });

    test('+15 s replaces the countdown and the workout scheduled', () async {
      await lockScreen.show(resting);
      clearInteractions(notifications);

      await lockScreen.show(resting);

      verifyInOrder([showsCountdown, schedulesWorkout]);
      verifyNever(() => notifications.cancel(any()));
    });

    test('outside a rest the workout counts up and no countdown '
        'shows', () async {
      expect((await lockScreen.show(training)).isOk, isTrue);

      verifyInOrder([
        // Unknown at start: one scheduled before is dropped.
        () => notifications.cancel(3),
        () => showsWorkout(training),
        () => notifications.cancel(2),
      ]);
    });

    test('a change of the workout replaces it in place', () async {
      await lockScreen.show(training);
      clearInteractions(notifications);

      await lockScreen.show(edited);

      verify(() => showsWorkout(edited)).called(1);
      verifyNever(() => notifications.cancel(3));
    });

    test('after a rest cut short, the workout scheduled for its end is '
        'dropped', () async {
      await lockScreen.show(resting);
      clearInteractions(notifications);

      await lockScreen.show(edited);

      verifyInOrder([
        () => notifications.cancel(3),
        () => showsWorkout(edited),
        () => notifications.cancel(2),
      ]);
    });

    test('a failure stops there and leaves it unknown', () async {
      await lockScreen.show(training);
      when(
        () => notifications.showCountdown(
          any(),
          endsAt: any(named: 'endsAt'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async => const Err(UnknownFailure('denied')));
      clearInteractions(notifications);

      final result = await lockScreen.show(resting);

      expect(result.failureOrNull, isA<UnknownFailure>());
      verifyNever(() => notifications.cancel(any()));
      verifyNever(schedulesWorkout);

      await lockScreen.show(training);
      verify(() => notifications.cancel(3)).called(1);
    });

    test('clear removes both, never the rest notification', () async {
      await lockScreen.clear();

      verify(() => notifications.cancel(2)).called(1);
      verify(() => notifications.cancel(3)).called(1);
      verifyNever(() => notifications.cancel(1));
    });

    test('has no taps or rest buttons of its own', () async {
      expect(await lockScreen.taps().isEmpty, isTrue);
      expect(await lockScreen.restActions().isEmpty, isTrue);
    });
  });

  group('iOS', () {
    late MockLiveActivity activity;
    late IosWorkoutLockScreen ios;

    setUp(() {
      activity = MockLiveActivity();
      ios = IosWorkoutLockScreen(
        restButtons: () => (shorten: '−15 s', extend: '+15 s', skip: 'Skip'),
        activity: activity,
      );
      when(() => activity.show(any(), staleAt: any(named: 'staleAt')))
          .thenAnswer((_) async => const Ok(null));
    });

    final set = {
      'exercise': 'Squat',
      'position': 'Exercise 1 of 4',
      'line': 'Set 2 of 3 · 80 kg × 8',
      'done': [true, false, false],
    };

    test('show sends the workout, times in milliseconds', () async {
      expect((await ios.show(training)).isOk, isTrue);
      verify(
        () => activity.show({
          'name': 'Legs',
          'startedAt': startedAt.millisecondsSinceEpoch,
          'set': set,
          'rest': null,
        }),
      ).called(1);
    });

    test('and its rest with its buttons, stale from its end', () async {
      await ios.show(resting);
      verify(
        () => activity.show({
          'name': 'Legs',
          'startedAt': startedAt.millisecondsSinceEpoch,
          'set': set,
          'rest': {
            'startsAt': rest.startsAt.millisecondsSinceEpoch,
            'endsAt': rest.endsAt.millisecondsSinceEpoch,
            'title': 'Rest',
            'detail': 'Next: Squat, set 2',
            'shorten': '−15 s',
            'extend': '+15 s',
            'skip': 'Skip',
          },
        }, staleAt: rest.endsAt),
      ).called(1);
    });

    test('without a set left it sends none', () async {
      await ios.show(LockScreenWorkout(name: 'Legs', startedAt: startedAt));
      final content =
          verify(() => activity.show(captureAny(), staleAt: null))
                  .captured
                  .single
              as Map;
      expect(content['set'], isNull);
    });

    test('a failure to show is passed on, to try again', () async {
      when(() => activity.show(any(), staleAt: any(named: 'staleAt')))
          .thenAnswer((_) async => const Err(UnknownFailure('turned off')));
      final result = await ios.show(training);
      expect(result.failureOrNull, isA<UnknownFailure>());
    });

    test('clear ends it', () async {
      when(activity.end).thenAnswer((_) async => const Ok(null));
      expect((await ios.clear()).isOk, isTrue);
      verify(activity.end).called(1);
    });

    test('taps are the activity\'s', () async {
      when(activity.taps).thenAnswer((_) => Stream.value(null));
      expect(await ios.taps().length, 1);
    });

    test('rest presses become rest actions, answered when handled; '
        'unknown ones are answered and dropped', () async {
      final handled = <String>[];
      LiveActivityPress press(String action) =>
          LiveActivityPress(action, onHandled: () => handled.add(action));
      when(activity.presses).thenAnswer(
        (_) => Stream.fromIterable([press('extend'), press('unknown')]),
      );

      final presses = await ios.restActions().toList();

      expect(presses.single.action, LockScreenRestAction.extend);
      expect(handled, ['unknown']);
      presses.single.handled();
      expect(handled, ['unknown', 'extend']);
    });
  });
}
