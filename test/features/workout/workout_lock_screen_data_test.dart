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
    endsAt: DateTime.utc(2026, 11, 11, 18, 2),
    title: 'Rest',
    detail: 'Next: Squat, set 2',
  );
  final training = LockScreenWorkout(
    name: 'Legs',
    startedAt: startedAt,
    current: 'Squat · set 2 of 3',
  );
  final resting = LockScreenWorkout(
    name: 'Legs',
    startedAt: startedAt,
    current: 'Squat · set 2 of 3',
    rest: rest,
  );
  setUpAll(() => registerFallbackValue(DateTime(2000)));

  group('Android', () {
    late MockNotifications notifications;
    late AndroidWorkoutLockScreen lockScreen;

    setUp(() {
      notifications = MockNotifications();
      lockScreen = AndroidWorkoutLockScreen(Future.value(notifications));
      when(() => notifications.cancel(any()))
          .thenAnswer((_) async => const Ok(null));
    });

    test('shows a rest as a countdown on its own id', () async {
      when(
        () => notifications.showCountdown(
          any(),
          endsAt: any(named: 'endsAt'),
          title: any(named: 'title'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => const Ok(null));

      expect((await lockScreen.show(resting)).isOk, isTrue);

      verify(
        () => notifications.showCountdown(
          2,
          endsAt: rest.endsAt,
          title: 'Rest',
          body: 'Next: Squat, set 2',
        ),
      ).called(1);
    });

    test('shows nothing outside a rest', () async {
      expect((await lockScreen.show(training)).isOk, isTrue);

      verify(() => notifications.cancel(2)).called(1);
      verifyNever(
        () => notifications.showCountdown(
          any(),
          endsAt: any(named: 'endsAt'),
          title: any(named: 'title'),
          body: any(named: 'body'),
        ),
      );
    });

    test('clear cancels that id only, never the rest notification', () async {
      await lockScreen.clear();

      verify(() => notifications.cancel(2)).called(1);
      verifyNever(() => notifications.cancel(1));
    });

    test('has no taps', () async {
      expect(await lockScreen.taps().isEmpty, isTrue);
    });
  });

  group('iOS', () {
    const methods = MethodChannel('getworkout/workout_activity');
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

    test('show sends the workout, times in milliseconds', () async {
      expect((await const IosWorkoutLockScreen().show(training)).isOk, isTrue);
      expect(calls.single.method, 'show');
      expect(calls.single.arguments, {
        'name': 'Legs',
        'startedAt': startedAt.millisecondsSinceEpoch,
        'current': 'Squat · set 2 of 3',
        'restEndsAt': null,
        'restTitle': null,
        'restDetail': null,
      });
    });

    test('and its rest', () async {
      await const IosWorkoutLockScreen().show(resting);
      expect(calls.single.arguments, {
        'name': 'Legs',
        'startedAt': startedAt.millisecondsSinceEpoch,
        'current': 'Squat · set 2 of 3',
        'restEndsAt': rest.endsAt.millisecondsSinceEpoch,
        'restTitle': 'Rest',
        'restDetail': 'Next: Squat, set 2',
      });
    });

    test('Live Activities turned off is a failure, to try again', () async {
      shows = false;
      final result = await const IosWorkoutLockScreen().show(training);
      expect(result.failureOrNull, isA<UnknownFailure>());
    });

    test('below iOS 16.2 (no answer) is no failure', () async {
      shows = null;
      expect((await const IosWorkoutLockScreen().show(training)).isOk, isTrue);
    });

    test('a native failure is a failure, not a throw', () async {
      final result = await const IosWorkoutLockScreen().clear();
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
        final subscription = const IosWorkoutLockScreen().taps().listen(
          taps.add,
        );
        await pumpEventQueue();
        expect(taps, hasLength(1));
        expect(calls.single.method, 'takeTap');
        await subscription.cancel();
      });

      test('a later one is taken when the Runner says so, once', () async {
        final taps = <void>[];
        final subscription = const IosWorkoutLockScreen().taps().listen(
          taps.add,
        );
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
  });
}
