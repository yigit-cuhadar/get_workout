import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/workout/domain/rest_notifications.dart';
import 'package:get_workout/features/workout/domain/rest_usecases.dart';
import 'package:mocktail/mocktail.dart';

class MockRestNotifications extends Mock implements RestNotifications {}

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
    test('asks on a device not asked yet that does not allow it, with no '
        'wish', () async {
      device(asked: const Ok(false));
      expect(await shouldAsk(null), RestNotifyAsk.ask);
    });

    test('a device not asked yet that already allows it is a yes, with no '
        'wish', () async {
      device(asked: const Ok(false), allowed: const Ok(true));
      expect(await shouldAsk(null), RestNotifyAsk.allow);
    });

    test('asks with no wish when the device cannot tell whether it allows '
        'it', () async {
      device(asked: const Ok(false), allowed: const Err(UnknownFailure('x')));
      expect(await shouldAsk(null), RestNotifyAsk.ask);
    });

    test('asks once a yes meets a device that does not allow it', () async {
      device(asked: const Ok(false));
      expect(await shouldAsk(true), RestNotifyAsk.ask);
    });

    test('not when the device already allows a yes', () async {
      device(asked: const Ok(false), allowed: const Ok(true));
      expect(await shouldAsk(true), RestNotifyAsk.none);
    });

    test('never after a no, nor twice on a device', () async {
      device(asked: const Ok(false), allowed: const Ok(true));
      expect(await shouldAsk(false), RestNotifyAsk.none);
      device(asked: const Ok(true), allowed: const Ok(true));
      expect(await shouldAsk(null), RestNotifyAsk.none);
      expect(await shouldAsk(true), RestNotifyAsk.none);
    });

    test('not when the device cannot tell', () async {
      device(asked: const Err(UnknownFailure('disk')));
      expect(await shouldAsk(null), RestNotifyAsk.none);
      device(asked: const Ok(false), allowed: const Err(UnknownFailure('x')));
      expect(await shouldAsk(true), RestNotifyAsk.none);
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
}
