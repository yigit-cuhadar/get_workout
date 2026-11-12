import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_photo_sync.dart';
import 'package:get_workout/features/body/domain/body_photos.dart';

import 'body_fakes.dart';

void main() {
  const front = 'users/u1/photos/e1/front-1.jpg';
  const back = 'users/u1/photos/e1/back-1.jpg';
  const othersPhoto = 'users/u2/photos/e9/front-1.jpg';

  late FakeBackupQueue queue;
  late FakePhotoStore store;
  late FakeBackup backup;
  late StreamController<String?> users;
  late BodyPhotoSync sync;

  void build([Map<String, BackupState> stored = const {}]) {
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

  test('a queued upload is done and remembered as uploaded', () async {
    sync.start(users.stream);
    await signIn('u1');
    store.files[front] = 'local/front';

    await sync.upload([front]);
    await pumpEventQueue();

    expect(backup.remote, {front: 'local/front'});
    expect(queue.saved, {front: BackupState.uploaded});
  });

  test('nothing runs while signed out; the queue is kept', () async {
    sync.start(users.stream);
    store.files[front] = 'local/front';

    await sync.upload([front]);
    await pumpEventQueue();

    expect(backup.calls, isEmpty);
    expect(queue.saved, {front: BackupState.upload});
  });

  test('offline work stays queued and is done on a later run', () async {
    sync.start(users.stream);
    await signIn('u1');
    store.files[front] = 'local/front';
    backup.online = false;

    await sync.upload([front]);
    await pumpEventQueue();
    expect(queue.saved, {front: BackupState.upload});

    backup.online = true;
    await sync.run();

    expect(backup.remote, {front: 'local/front'});
    expect(queue.saved, {front: BackupState.uploaded});
  });

  test('work queued before a restart is picked up on sign-in', () async {
    build({front: BackupState.upload, back: BackupState.delete});
    store.files[front] = 'local/front';
    backup.remote[back] = 'old';
    sync.start(users.stream);

    await signIn('u1');

    expect(backup.remote, {front: 'local/front'});
    expect(queue.saved, {front: BackupState.uploaded});
  });

  test("another user's work waits for them", () async {
    build({othersPhoto: BackupState.delete});
    sync.start(users.stream);

    await signIn('u1');

    expect(backup.calls, isEmpty);
    expect(queue.saved, {othersPhoto: BackupState.delete});
  });

  test('a delete queued while its upload runs is done after it', () async {
    sync.start(users.stream);
    await signIn('u1');
    store.files[front] = 'local/front';
    final gate = backup.gate = Completer<void>();

    await sync.upload([front]);
    await pumpEventQueue();
    expect(backup.calls, ['upload $front']);

    await sync.delete([front]);
    gate.complete();
    await pumpEventQueue();

    expect(backup.calls, ['upload $front', 'delete $front']);
    expect(backup.remote, isEmpty);
    expect(queue.saved, isEmpty);
  });

  test('a user change while a task runs goes on with the new user', () async {
    const theirs = 'users/u2/photos/e2/front-1.jpg';
    store.files[front] = 'local/front';
    store.files[theirs] = 'local/theirs';
    build({front: BackupState.upload, theirs: BackupState.upload});
    sync.start(users.stream);
    final gate = backup.gate = Completer<void>();
    await signIn('u1');
    expect(backup.calls, ['upload $front']);

    // The sign-out makes the running upload fail.
    backup.refused.add(front);
    await signIn('u2');
    gate.complete();
    await pumpEventQueue();

    expect(backup.calls, ['upload $front', 'upload $theirs']);
    expect(queue.saved, {
      front: BackupState.upload,
      theirs: BackupState.uploaded,
    });
  });

  test('a photo gone from the device before its upload is dropped', () async {
    sync.start(users.stream);
    await signIn('u1');

    await sync.upload([front]);
    await pumpEventQueue();

    expect(backup.calls, isEmpty);
    expect(queue.saved, {front: BackupState.uploaded});
  });

  group('reconcile', () {
    final entry = BodyEntry(
      id: 'e1',
      date: DateTime(2026, 11, 1),
      photos: const {PhotoPose.front: front, PhotoPose.back: back},
    );

    test(
      'after a lost queue, uploads the photos on the device again',
      () async {
        store.files[front] = 'local/front';
        queue.loadFailure = const UnknownFailure('unreadable');
        sync.start(users.stream);
        await signIn('u1');

        await sync.reconcile('u1', [entry]);
        await pumpEventQueue();

        // The back photo is not on this device: nothing to upload.
        expect(backup.calls, ['upload $front']);
        expect(queue.saved, {front: BackupState.uploaded});
      },
    );

    test('leaves photos the queue knows', () async {
      store.files[front] = 'local/front';
      build({front: BackupState.uploaded});
      sync.start(users.stream);
      await signIn('u1');

      await sync.reconcile('u1', [entry]);
      await pumpEventQueue();

      expect(backup.calls, isEmpty);
    });
  });

  group('forget', () {
    test(
      'drops the user\'s work and photos once the running task ended',
      () async {
        store.files[front] = 'local/front';
        store.files[othersPhoto] = 'local/theirs';
        build({front: BackupState.upload, othersPhoto: BackupState.delete});
        sync.start(users.stream);
        final gate = backup.gate = Completer<void>();
        await signIn('u1');

        final forgetting = sync.forget('u1');
        await pumpEventQueue();
        expect(store.forgotten, isEmpty);

        gate.complete();
        expect((await forgetting).isOk, isTrue);

        expect(store.forgotten, ['u1']);
        expect(store.files.keys, [othersPhoto]);
        expect(queue.saved, {othersPhoto: BackupState.delete});
      },
    );
  });

  group('restore', () {
    test('returns a photo on the device without the network', () async {
      sync.start(users.stream);
      await signIn('u1');
      store.files[front] = 'local/front';

      expect(await sync.restore(front), 'local/front');
      expect(backup.calls, isEmpty);
    });

    test('fetches a missing photo into the store, known as uploaded', () async {
      sync.start(users.stream);
      await signIn('u1');
      backup.remote[front] = 'cloud';

      expect(await sync.restore(front), 'local/$front');
      expect(store.bytes[front], [1, 2, 3]);
      expect(queue.saved, {front: BackupState.uploaded});
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
