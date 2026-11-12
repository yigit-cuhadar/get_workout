import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_workout/features/account/data/device_account_data.dart';
import 'package:get_workout/features/body/domain/body_photos.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../body/body_fakes.dart';

class MockStore extends Mock implements LocalWorkoutStore {}

class MockNotifications extends Mock implements Notifications {}

class MockFirestore extends Mock implements FirebaseFirestore {}

void main() {
  late Directory directory;
  late MockStore store;
  late MockNotifications notifications;
  late MockFirestore firestore;
  late DeviceAccountData data;
  late BodyPhotoWorld photos;

  Future<Directory> support() async => Directory('${directory.path}/support');

  setUp(() {
    directory = Directory.systemTemp.createTempSync('account_data');
    store = MockStore();
    notifications = MockNotifications();
    firestore = MockFirestore();
    photos = BodyPhotoWorld();
    data = DeviceAccountData(
      store,
      Future.value(notifications),
      support,
      stopPhotoBackup: StopBodyPhotoBackup(photos.sync),
      resumePhotoBackup: ResumeBodyPhotoBackup(photos.sync),
      forgetPhotos: ForgetBodyPhotos(photos.sync),
    );
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

  test("removes the user's photos and their backup queue", () async {
    const mine = 'users/u1/photos/e1/front-1.jpg';
    const theirs = 'users/u2/photos/e2/front-1.jpg';
    photos.store.files
      ..[mine] = 'local/mine'
      ..[theirs] = 'local/theirs';
    await photos.sync.upload([mine, theirs]);

    expect((await data.clear('u1')).isOk, isTrue);

    expect(photos.store.forgotten, ['u1']);
    expect(photos.store.files.keys, [theirs]);
    expect(photos.queue.saved, {theirs: BackupState.upload});
  });

  test('holding writes stops the photo backup until released', () async {
    const mine = 'users/u1/photos/e1/front-1.jpg';
    photos.store.files[mine] = 'local/mine';
    photos.sync.start(Stream.value((id: 'u1', guest: false)));
    photos.backup.online = false;
    await photos.sync.upload([mine]);
    await pumpEventQueue();

    await data.holdWrites('u1');
    expect(photos.queue.saved, isEmpty);
    photos.backup.online = true;
    await photos.sync.upload([mine]);
    await pumpEventQueue();
    expect(photos.backup.remote, isEmpty);

    await data.releaseWrites('u1');
    await photos.sync.upload([mine]);
    await pumpEventQueue();
    expect(photos.backup.remote.keys, [mine]);
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
