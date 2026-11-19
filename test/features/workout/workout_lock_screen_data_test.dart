import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_workout/features/workout/data/android_workout_lock_screen.dart';
import 'package:get_workout/features/workout/data/ios_workout_lock_screen.dart';
import 'package:get_workout/features/workout/domain/workout_lock_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockNotifications extends Mock implements Notifications {}

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
  setUpAll(() => registerFallbackValue(DateTime(2000)));

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
    const methods = MethodChannel('getworkout/workout_activity');
    const restMethods = MethodChannel('getworkout/workout_activity_rest');
    IosWorkoutLockScreen ios() => IosWorkoutLockScreen(
      restButtons: () => (shorten: '−15 s', extend: '+15 s', skip: 'Skip'),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;
    late bool? shows;
    late bool tapped;

    setUp(() {
      calls = [];
      shows = true;
      tapped = false;
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'end':
            throw PlatformException(code: 'boom');
          case 'takeTap':
            final was = tapped;
            tapped = false;
            return was;
        }
        return shows;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(methods, null));

    final set = {
      'exercise': 'Squat',
      'position': 'Exercise 1 of 4',
      'line': 'Set 2 of 3 · 80 kg × 8',
      'done': [true, false, false],
    };

    test('show sends the workout, times in milliseconds', () async {
      expect((await ios().show(training)).isOk, isTrue);
      expect(calls.single.method, 'show');
      expect(calls.single.arguments, {
        'name': 'Legs',
        'startedAt': startedAt.millisecondsSinceEpoch,
        'set': set,
        'rest': null,
      });
    });

    test('and its rest with its buttons', () async {
      await ios().show(resting);
      expect(calls.single.arguments, {
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
      });
    });

    test('without a set left it sends none', () async {
      await ios().show(LockScreenWorkout(name: 'Legs', startedAt: startedAt));
      expect((calls.single.arguments as Map)['set'], isNull);
    });

    test('Live Activities turned off is a failure, to try again', () async {
      shows = false;
      final result = await ios().show(training);
      expect(result.failureOrNull, isA<UnknownFailure>());
    });

    test('below iOS 16.2 (no answer) is no failure', () async {
      shows = null;
      expect((await ios().show(training)).isOk, isTrue);
    });

    test('a native failure is a failure, not a throw', () async {
      final result = await ios().clear();
      expect(calls.single.method, 'end');
      expect(result.failureOrNull, isA<UnknownFailure>());
    });

    group('taps', () {
      Future<void> nativeSays(String method) => messenger.handlePlatformMessage(
        methods.name,
        methods.codec.encodeMethodCall(MethodCall(method)),
        (_) {},
      );

      test('the one that launched the app is taken on listening', () async {
        tapped = true;
        final taps = <void>[];
        final subscription = ios().taps().listen(taps.add);
        await pumpEventQueue();
        expect(taps, hasLength(1));
        expect(calls.single.method, 'takeTap');
        await subscription.cancel();
      });

      test('a later one is taken when the Runner says so, once', () async {
        final taps = <void>[];
        final subscription = ios().taps().listen(taps.add);
        await pumpEventQueue();
        expect(taps, isEmpty);

        tapped = true;
        await nativeSays('tapped');
        await nativeSays('tapped');
        await pumpEventQueue();
        expect(taps, hasLength(1));
        await subscription.cancel();
      });
    });

    group('rest buttons', () {
      late List<String> kept;

      setUp(() {
        kept = [];
        messenger.setMockMethodCallHandler(restMethods, (call) async {
          calls.add(call);
          final taken = kept;
          kept = [];
          return taken;
        });
      });

      tearDown(() => messenger.setMockMethodCallHandler(restMethods, null));

      Future<void> nativeSays(String action) => messenger.handlePlatformMessage(
        restMethods.name,
        restMethods.codec.encodeMethodCall(MethodCall('restAction', action)),
        (_) {},
      );

      test('those pressed while the app did not run are taken on '
          'listening', () async {
        kept = ['extend', 'skip'];
        final actions = <LockScreenRestAction>[];
        final subscription = ios().restActions().listen(actions.add);
        await pumpEventQueue();
        expect(calls.single.method, 'takeRestActions');
        expect(actions, [
          LockScreenRestAction.extend,
          LockScreenRestAction.skip,
        ]);
        await subscription.cancel();
      });

      test('later ones come as the Runner sends them', () async {
        final actions = <LockScreenRestAction>[];
        final subscription = ios().restActions().listen(actions.add);
        await pumpEventQueue();
        await nativeSays('shorten');
        await nativeSays('unknown');
        await pumpEventQueue();
        expect(actions, [LockScreenRestAction.shorten]);
        await subscription.cancel();
      });
    });
  });
}
