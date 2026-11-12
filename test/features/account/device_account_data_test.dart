import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_workout/features/account/data/device_account_data.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockStore extends Mock implements LocalWorkoutStore {}

class MockNotifications extends Mock implements Notifications {}

class MockFirestore extends Mock implements FirebaseFirestore {}

void main() {
  late Directory directory;
  late MockStore store;
  late MockNotifications notifications;
  late MockFirestore firestore;
  late DeviceAccountData data;

  Future<Directory> support() async => Directory('${directory.path}/support');

  setUp(() {
    directory = Directory.systemTemp.createTempSync('account_data');
    store = MockStore();
    notifications = MockNotifications();
    firestore = MockFirestore();
    data = DeviceAccountData(store, Future.value(notifications), support);
    when(() => store.remove(any())).thenAnswer((_) async => const Ok(null));
    when(() => notifications.cancelAll())
        .thenAnswer((_) async => const Ok(null));
    when(() => firestore.clearPersistence()).thenAnswer((_) async {});
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('removes the kept workouts and every scheduled notification', () async {
    expect((await data.clear('u1')).isOk, isTrue);
    verify(() => store.remove('u1')).called(1);
    verify(() => notifications.cancelAll()).called(1);
  });

  test('one part failing still does the others, and is reported', () async {
    when(() => store.remove(any()))
        .thenAnswer((_) async => const Err(UnknownFailure()));
    expect((await data.clear('u1')).failureOrNull, isA<UnknownFailure>());
    verify(() => notifications.cancelAll()).called(1);
  });

  group('the offline copy', () {
    test('is left alone at a start without a deletion', () async {
      await DeviceAccountData.clearOfflineCopyIfMarked(support, firestore);
      verifyNever(() => firestore.clearPersistence());
    });

    test('is cleared at the next start after a deletion, once', () async {
      await data.clear('u1');
      verifyNever(() => firestore.clearPersistence());

      await DeviceAccountData.clearOfflineCopyIfMarked(support, firestore);
      verify(() => firestore.clearPersistence()).called(1);

      await DeviceAccountData.clearOfflineCopyIfMarked(support, firestore);
      verifyNever(() => firestore.clearPersistence());
    });

    test('a failed clear is tried again at the start after', () async {
      await data.clear('u1');
      when(() => firestore.clearPersistence()).thenThrow(Exception('in use'));
      await DeviceAccountData.clearOfflineCopyIfMarked(support, firestore);

      when(() => firestore.clearPersistence()).thenAnswer((_) async {});
      await DeviceAccountData.clearOfflineCopyIfMarked(support, firestore);
      verify(() => firestore.clearPersistence()).called(2);
    });
  });
}
