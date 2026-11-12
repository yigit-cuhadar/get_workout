import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/workout/domain/rest_lock_screen.dart';
import 'package:get_workout/features/workout/domain/rest_notifications.dart';
import 'package:get_workout/features/workout/domain/rest_usecases.dart';
import 'package:mocktail/mocktail.dart';

class MockRestNotifications extends Mock implements RestNotifications {}

class MockRestLockScreen extends Mock implements RestLockScreen {}

void main() {
  late MockRestNotifications notifications;
  late ShouldAskRestNotifications shouldAsk;

  void device({
    required Result<bool> asked,
    Result<bool> allowed = const Ok(false),
  }) {
    when(notifications.askedHere).thenAnswer((_) async => asked);
    when(notifications.allowed).thenAnswer((_) async => allowed);
  }

  setUp(() {
    notifications = MockRestNotifications();
    shouldAsk = ShouldAskRestNotifications(notifications);
  });

  group('ShouldAskRestNotifications', () {
    test('asks on a device not asked yet, with no wish', () async {
      device(asked: const Ok(false));
      expect(await shouldAsk(null), isTrue);
    });

    test('asks once a yes meets a device that does not allow it', () async {
      device(asked: const Ok(false));
      expect(await shouldAsk(true), isTrue);
    });

    test('not when the device already allows a yes', () async {
      device(asked: const Ok(false), allowed: const Ok(true));
      expect(await shouldAsk(true), isFalse);
    });

    test('never after a no, nor twice on a device', () async {
      device(asked: const Ok(false));
      expect(await shouldAsk(false), isFalse);
      device(asked: const Ok(true));
      expect(await shouldAsk(null), isFalse);
      expect(await shouldAsk(true), isFalse);
    });

    test('not when the device cannot tell', () async {
      device(asked: const Err(UnknownFailure('disk')));
      expect(await shouldAsk(null), isFalse);
      device(asked: const Ok(false), allowed: const Err(UnknownFailure('x')));
      expect(await shouldAsk(true), isFalse);
    });
  });

  test('allowing marks the device asked, then asks the device', () async {
    when(notifications.markAskedHere).thenAnswer((_) async => const Ok(null));
    when(notifications.request).thenAnswer((_) async => const Ok(true));
    final result = await AllowRestNotifications(notifications)(
      const NoParams(),
    );
    expect(result.valueOrNull, isTrue);
    verifyInOrder([notifications.markAskedHere, notifications.request]);
  });

  test('declining only marks the device asked', () async {
    when(notifications.markAskedHere).thenAnswer((_) async => const Ok(null));
    await DeclineRestNotifications(notifications)(const NoParams());
    verify(notifications.markAskedHere).called(1);
    verifyNever(notifications.request);
  });

  group('lock screen', () {
    late MockRestLockScreen lockScreen;
    final countdown = RestCountdown(
      endsAt: DateTime(2026, 11, 11, 18, 2),
      title: 'Rest',
      detail: 'Next: Squat, set 2',
      over: 'Rest over',
    );

    setUp(() => lockScreen = MockRestLockScreen());

    test('showing passes the countdown and its result on', () async {
      when(() => lockScreen.show(countdown))
          .thenAnswer((_) async => const Err(UnknownFailure('off')));
      final result = await ShowRestOnLockScreen(lockScreen)(countdown);
      expect(result.failureOrNull, isA<UnknownFailure>());
      verify(() => lockScreen.show(countdown)).called(1);
    });

    test('clearing clears', () async {
      when(lockScreen.clear).thenAnswer((_) async => const Ok(null));
      final result = await ClearRestFromLockScreen(lockScreen)(
        const NoParams(),
      );
      expect(result.isOk, isTrue);
      verify(lockScreen.clear).called(1);
    });
  });
}
