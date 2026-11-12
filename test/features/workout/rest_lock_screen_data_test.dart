import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_workout/features/workout/data/android_rest_lock_screen.dart';
import 'package:get_workout/features/workout/data/ios_rest_lock_screen.dart';
import 'package:get_workout/features/workout/domain/rest_lock_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockNotifications extends Mock implements Notifications {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final countdown = RestCountdown(
    endsAt: DateTime.utc(2026, 11, 11, 18, 2),
    title: 'Rest',
    detail: 'Next: Squat, set 2',
    over: 'Rest over',
  );
  setUpAll(() => registerFallbackValue(DateTime(2000)));

  group('Android', () {
    late MockNotifications notifications;
    late AndroidRestLockScreen lockScreen;

    setUp(() {
      notifications = MockNotifications();
      lockScreen = AndroidRestLockScreen(Future.value(notifications));
    });

    test('shows a countdown on its own id', () async {
      when(
        () => notifications.showCountdown(
          any(),
          endsAt: any(named: 'endsAt'),
          title: any(named: 'title'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => const Ok(null));

      expect((await lockScreen.show(countdown)).isOk, isTrue);

      verify(
        () => notifications.showCountdown(
          2,
          endsAt: countdown.endsAt,
          title: 'Rest',
          body: 'Next: Squat, set 2',
        ),
      ).called(1);
    });

    test('clear cancels that id only, never the rest notification', () async {
      when(() => notifications.cancel(any()))
          .thenAnswer((_) async => const Ok(null));

      await lockScreen.clear();

      verify(() => notifications.cancel(2)).called(1);
      verifyNever(() => notifications.cancel(1));
    });
  });

  group('iOS', () {
    const methods = MethodChannel('getworkout/rest_activity');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;
    late bool? shows;

    setUp(() {
      calls = [];
      shows = true;
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        if (call.method == 'end') {
          throw PlatformException(code: 'boom');
        }
        return shows;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(methods, null));

    test('show sends the end in milliseconds and every text', () async {
      expect((await const IosRestLockScreen().show(countdown)).isOk, isTrue);
      expect(calls.single.method, 'show');
      expect(calls.single.arguments, {
        'endsAt': countdown.endsAt.millisecondsSinceEpoch,
        'title': 'Rest',
        'detail': 'Next: Squat, set 2',
        'over': 'Rest over',
      });
    });

    test('Live Activities turned off is a failure, to try again', () async {
      shows = false;
      final result = await const IosRestLockScreen().show(countdown);
      expect(result.failureOrNull, isA<UnknownFailure>());
    });

    test('below iOS 16.2 (no answer) is no failure', () async {
      shows = null;
      expect((await const IosRestLockScreen().show(countdown)).isOk, isTrue);
    });

    test('a native failure is a failure, not a throw', () async {
      final result = await const IosRestLockScreen().clear();
      expect(calls.single.method, 'end');
      expect(result.failureOrNull, isA<UnknownFailure>());
    });
  });
}
