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
  late StreamController<BodyPhotoUser?> users;
  late FakeBodyRepository repository;
  late DateTime now;
  late BodyPhotoSync sync;

  void build([Map<String, BackupState> stored = const {}]) {
    queue = FakeBackupQueue(stored);
    sync = BodyPhotoSync(queue, store, backup, repository, clock: () => now);
  }

  setUp(() {
    store = FakePhotoStore();
    backup = FakeBackup();
    users = StreamController<BodyPhotoUser?>();
    repository = FakeBodyRepository();
    now = DateTime(2026, 11, 12, 9);
    build();
  });

  tearDown(() async {
    await sync.cancel();
    await users.close();
  });

  Future<void> signIn(String? uid, {bool guest = false}) async {
    users.add(uid == null ? null : (id: uid, guest: guest));
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

  group('stop and resume', () {
    test(
      'a stopped user\'s queue is dropped and nothing new is sent',
      () async {
        store.files[front] = 'local/front';
        build({front: BackupState.upload});
        backup.online = false;
        sync.start(users.stream);
        await signIn('u1');

        await sync.stop('u1');
        expect(queue.saved, isEmpty);

        backup.online = true;
        await sync.upload([front]);
        await sync.run();
        expect(backup.remote, isEmpty);
        expect(await sync.restore(back), isNull);

        await sync.resume('u1');
        await sync.upload([front]);
        await pumpEventQueue();
        expect(backup.remote.keys, [front]);
      },
    );

    test('stop waits for the upload in progress', () async {
      store.files[front] = 'local/front';
      sync.start(users.stream);
      await signIn('u1');
      final gate = backup.gate = Completer<void>();
      await sync.upload([front]);
      await pumpEventQueue();

      var stopped = false;
      final stopping = sync.stop('u1').then((_) => stopped = true);
      await pumpEventQueue();
      expect(stopped, isFalse);

      gate.complete();
      await stopping;
      expect(queue.saved, isEmpty);
    });
  });

  test(
    "a guest who is left has their photos forgotten; an account's stay",
    () async {
      const guestPhoto = 'users/g1/photos/e1/front-1.jpg';
      store.files
        ..[guestPhoto] = 'local/guest'
        ..[front] = 'local/front';
      sync.start(users.stream);

      await signIn('g1', guest: true);
      await signIn('u1');
      await pumpEventQueue();
      expect(store.forgotten, ['g1']);

      await signIn(null);
      await pumpEventQueue();
      expect(store.forgotten, ['g1']);
      expect(store.files.keys, [front]);
    },
  );

  group('orphaned photos', () {
    const named = 'users/u1/photos/e1/front-1.jpg';
    const orphan = 'users/u1/photos/gone/front-1.jpg';
    const queued = 'users/u1/photos/gone/back-1.jpg';
    const fresh = 'users/u1/photos/new/front-1.jpg';
    const theirs = 'users/u2/photos/x/front-1.jpg';

    setUp(() {
      repository.entries['e1'] = BodyEntry(
        id: 'e1',
        date: DateTime(2026, 11, 1),
        photos: const {PhotoPose.front: named},
      );
      for (final path in [named, orphan, queued, fresh, theirs]) {
        store.files[path] = 'local/$path';
      }
      store.written[fresh] = now.subtract(const Duration(minutes: 2));
      backup.online = false;
      build({queued: BackupState.upload});
    });

    test('are removed once the server answered: not named, not queued, '
        'not recent, only the user\'s', () async {
      sync.start(users.stream);
      await signIn('u1');
      expect(store.files.keys, contains(orphan));

      repository.server.complete();
      await pumpEventQueue();

      expect(store.files.keys, unorderedEquals([named, queued, fresh, theirs]));
    });

    test('are left while the server has not answered', () async {
      sync.start(users.stream);
      await signIn('u1');
      await pumpEventQueue();

      expect(store.files.keys, contains(orphan));
    });
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
