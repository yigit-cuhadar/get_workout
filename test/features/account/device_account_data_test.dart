import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_workout/features/account/data/device_account_data.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockStore extends Mock implements LocalWorkoutStore {}

class MockNotifications extends Mock implements Notifications {}

void main() {
  late MockStore store;
  late MockNotifications notifications;
  late DeviceAccountData data;

  setUp(() {
    store = MockStore();
    notifications = MockNotifications();
    data = DeviceAccountData(store, Future.value(notifications));
    when(() => store.remove(any())).thenAnswer((_) async => const Ok(null));
    when(() => notifications.cancelAll())
        .thenAnswer((_) async => const Ok(null));
  });

  test('removes the kept workouts and every scheduled notification', () async {
    expect((await data.clear('u1')).isOk, isTrue);
    verify(() => store.remove('u1')).called(1);
    verify(() => notifications.cancelAll()).called(1);
  });

  test('one part failing still does the other, and is reported', () async {
    when(() => store.remove(any()))
        .thenAnswer((_) async => const Err(UnknownFailure()));
    expect((await data.clear('u1')).failureOrNull, isA<UnknownFailure>());
    verify(() => notifications.cancelAll()).called(1);
  });
}
