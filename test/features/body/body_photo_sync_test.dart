import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/domain/body_photo_sync.dart';
import 'package:get_workout/features/body/domain/body_photos.dart';

import 'body_fakes.dart';

void main() {
  const front = 'users/u1/photos/e1/front.jpg';
  const back = 'users/u1/photos/e1/back.jpg';
  const othersPhoto = 'users/u2/photos/e9/front.jpg';

  late FakeBackupQueue queue;
  late FakePhotoStore store;
  late FakeBackup backup;
  late StreamController<String?> users;
  late BodyPhotoSync sync;

  void build([Map<String, BackupTask> stored = const {}]) {
    queue = FakeBackupQueue(stored);
    sync = BodyPhotoSync(queue, store, backup);
  }

  setUp(() {
    store = FakePhotoStore();
    backup = FakeBackup();
    users = StreamController<String?>();
    build();
  });

  tearDown(() async {
    await sync.cancel();
    await users.close();
  });

  Future<void> signIn(String? uid) async {
    users.add(uid);
    await pumpEventQueue();
  }

  test('a queued upload is done for the signed-in user', () async {
    sync.start(users.stream);
    await signIn('u1');
    store.files[front] = 'local/front';

    await sync.upload(front);
    await pumpEventQueue();

    expect(backup.remote, {front: 'local/front'});
    expect(queue.saved, isEmpty);
  });

  test('nothing runs while signed out; the queue is kept', () async {
    sync.start(users.stream);
    store.files[front] = 'local/front';

    await sync.upload(front);
    await pumpEventQueue();

    expect(backup.calls, isEmpty);
    expect(queue.saved, {front: BackupTask.upload});
  });

  test('offline work stays queued and is done on a later run', () async {
    sync.start(users.stream);
    await signIn('u1');
    store.files[front] = 'local/front';
    backup.online = false;

    await sync.upload(front);
    await pumpEventQueue();
    expect(queue.saved, {front: BackupTask.upload});

    backup.online = true;
    await sync.run();

    expect(backup.remote, {front: 'local/front'});
    expect(queue.saved, isEmpty);
  });

  test('work queued before a restart is picked up on sign-in', () async {
    build({front: BackupTask.upload, back: BackupTask.delete});
    store.files[front] = 'local/front';
    backup.remote[back] = 'old';
    sync.start(users.stream);

    await signIn('u1');

    expect(backup.remote, {front: 'local/front'});
    expect(queue.saved, isEmpty);
  });

  test("another user's work waits for them", () async {
    build({othersPhoto: BackupTask.delete});
    sync.start(users.stream);

    await signIn('u1');

    expect(backup.calls, isEmpty);
    expect(queue.saved, {othersPhoto: BackupTask.delete});
  });

  test('a delete replaces a pending upload of the same photo', () async {
    sync.start(users.stream);
    store.files[front] = 'local/front';
    await sync.upload(front);
    await sync.delete([front]);
    expect(queue.saved, {front: BackupTask.delete});

    await signIn('u1');

    expect(backup.calls, ['delete $front']);
    expect(queue.saved, isEmpty);
  });

  test('a photo gone from the device before its upload is dropped', () async {
    sync.start(users.stream);
    await signIn('u1');

    await sync.upload(front);
    await pumpEventQueue();

    expect(backup.calls, isEmpty);
    expect(queue.saved, isEmpty);
  });

  group('restore', () {
    test('returns a photo on the device without the network', () async {
      sync.start(users.stream);
      await signIn('u1');
      store.files[front] = 'local/front';

      expect(await sync.restore(front), 'local/front');
      expect(backup.calls, isEmpty);
    });

    test('fetches a missing photo from the backup into the store', () async {
      sync.start(users.stream);
      await signIn('u1');
      backup.remote[front] = 'cloud';

      expect(await sync.restore(front), 'local/$front');
      expect(store.bytes[front], [1, 2, 3]);
    });

    test('is null without a copy, offline, or for another user', () async {
      sync.start(users.stream);
      await signIn('u1');

      expect(await sync.restore(front), isNull);
      backup
        ..remote[front] = 'cloud'
        ..online = false;
      expect(await sync.restore(front), isNull);
      backup.online = true;
      backup.remote[othersPhoto] = 'cloud';
      expect(await sync.restore(othersPhoto), isNull);
    });

    test('does not bring back a photo queued for removal', () async {
      sync.start(users.stream);
      backup
        ..online = false
        ..remote[front] = 'cloud';
      await signIn('u1');
      await sync.delete([front]);
      await pumpEventQueue();
      backup.online = true;

      expect(await sync.restore(front), isNull);
    });
  });
}
