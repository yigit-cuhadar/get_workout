import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_photos.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';

import 'body_fakes.dart';

void main() {
  final now = DateTime(2026, 11, 12, 9);
  final rev = now.millisecondsSinceEpoch;
  const oldFront = 'users/u1/photos/e1/front-1.jpg';
  final newFront = 'users/u1/photos/e1/front-$rev.jpg';
  final newBack = 'users/u1/photos/e1/back-$rev.jpg';

  late BodyPhotoWorld world;

  setUp(() {
    world = BodyPhotoWorld();
  });

  group('save', () {
    test('stores the photos, writes the entry naming them, then queues '
        'uploads and removes the camera files', () async {
      final result = await world.save(() => now)((
        uid: 'u1',
        entry: BodyEntry(id: 'e1', date: now, weightKg: 80),
        newPhotos: {
          PhotoPose.front: '/tmp/a.jpg',
          PhotoPose.back: '/tmp/b.jpg',
        },
        isNew: true,
      ));

      expect(result.isOk, isTrue);
      expect(world.repository.entries['e1']!.photos, {
        PhotoPose.front: newFront,
        PhotoPose.back: newBack,
      });
      expect(world.store.files.keys, unorderedEquals([newFront, newBack]));
      expect(world.queue.saved, {
        newFront: BackupState.upload,
        newBack: BackupState.upload,
      });
      expect(world.store.discarded, ['/tmp/a.jpg', '/tmp/b.jpg']);
    });

    test('a photo that fails removes those stored; a retry under the same '
        'id saves it all', () async {
      final entry = BodyEntry(id: 'e1', date: now);
      final photos = {
        PhotoPose.front: '/tmp/a.jpg',
        PhotoPose.back: '/tmp/b.jpg',
      };
      world.store.failing.add('back');

      final failed = await world.save(() => now)((
        uid: 'u1',
        entry: entry,
        newPhotos: photos,
        isNew: true,
      ));

      expect(failed.isOk, isFalse);
      expect(world.store.files, isEmpty);
      expect(world.repository.calls, isEmpty);
      expect(world.queue.saved, isEmpty);
      expect(world.store.discarded, isEmpty);

      world.store.failing.clear();
      final retried = await world.save(() => now)((
        uid: 'u1',
        entry: entry,
        newPhotos: photos,
        isNew: true,
      ));

      expect(retried.isOk, isTrue);
      expect(world.repository.calls, ['add e1']);
      expect(world.store.files.keys, unorderedEquals([newFront, newBack]));
    });

    test('an entry that cannot be written removes the stored photos', () async {
      world.repository.startFailure = const UnknownFailure('cache full');

      final result = await world.save(() => now)((
        uid: 'u1',
        entry: BodyEntry(id: 'e1', date: now),
        newPhotos: {PhotoPose.front: '/tmp/a.jpg'},
        isNew: true,
      ));

      expect(result.isOk, isFalse);
      expect(world.store.files, isEmpty);
      expect(world.queue.saved, isEmpty);
    });

    test('a retake removes the replaced photo only once confirmed', () async {
      world.store.files[oldFront] = 'local/old';
      world.repository.holdConfirmations = true;

      await world.save(() => now)((
        uid: 'u1',
        entry: BodyEntry(
          id: 'e1',
          date: now,
          photos: const {PhotoPose.front: oldFront},
        ),
        newPhotos: {PhotoPose.front: '/tmp/a.jpg'},
        isNew: false,
      ));
      expect(world.store.files.keys, unorderedEquals([oldFront, newFront]));

      await world.repository.confirm();

      expect(world.store.files.keys, [newFront]);
      expect(world.queue.saved[oldFront], BackupState.delete);
    });

    test(
      'a refused save removes its new photos, here and queued remotely',
      () async {
        world.store.files[oldFront] = 'local/old';
        world.repository.holdConfirmations = true;

        await world.save(() => now)((
          uid: 'u1',
          entry: BodyEntry(
            id: 'e1',
            date: now,
            photos: const {PhotoPose.front: oldFront},
          ),
          newPhotos: {PhotoPose.front: '/tmp/a.jpg'},
          isNew: false,
        ));
        await world.repository.confirm(const PermissionFailure());

        expect(world.store.files.keys, [oldFront]);
        expect(world.queue.saved[newFront], BackupState.delete);
      },
    );

    test('an invalid entry writes nothing', () async {
      final result = await world.save(() => now)((
        uid: 'u1',
        entry: BodyEntry(id: 'w1', date: now, weightKg: 500),
        newPhotos: {PhotoPose.front: '/tmp/a.jpg'},
        isNew: true,
      ));

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(world.store.files, isEmpty);
      expect(world.repository.calls, isEmpty);
    });

    test('the profile weight follows the most recent weight', () async {
      world.profiles.profile = const UserProfile(weightKg: 90);
      world.repository.entries['new'] = BodyEntry(
        id: 'new',
        date: DateTime(2026, 11, 20),
        measurements: const {BodyMeasurement.waist: 80},
      );

      await world.save(() => now)((
        uid: 'u1',
        entry: BodyEntry(id: 'w1', date: now, weightKg: 82),
        newPhotos: const {},
        isNew: true,
      ));
      expect(world.profiles.profile.weightKg, 82);

      // An older weight logged later does not win.
      await world.save(() => now)((
        uid: 'u1',
        entry: BodyEntry(id: 'w0', date: DateTime(2026, 1, 1), weightKg: 99),
        newPhotos: const {},
        isNew: true,
      ));
      expect(world.profiles.profile.weightKg, 82);
    });
  });

  group('delete', () {
    final entry = BodyEntry(
      id: 'e1',
      date: now,
      weightKg: 80,
      photos: const {PhotoPose.front: oldFront},
    );

    test('removes the photos only once the server confirms', () async {
      world.repository.entries['e1'] = entry;
      world.store.files[oldFront] = 'local/old';
      world.repository.holdConfirmations = true;

      final result = await world.delete()((uid: 'u1', entry: entry));

      expect(result.isOk, isTrue);
      expect(world.store.files, isNotEmpty);
      expect(world.queue.saved, isEmpty);

      await world.repository.confirm();

      expect(world.store.files, isEmpty);
      expect(world.queue.saved, {oldFront: BackupState.delete});
    });

    test('a refused delete keeps the photos', () async {
      world.store.files[oldFront] = 'local/old';
      world.repository.holdConfirmations = true;

      await world.delete()((uid: 'u1', entry: entry));
      await world.repository.confirm(const PermissionFailure());

      expect(world.store.files, {oldFront: 'local/old'});
      expect(world.queue.saved, isEmpty);
    });

    test('a delete that cannot start keeps everything', () async {
      world.store.files[oldFront] = 'local/old';
      world.repository.startFailure = const NetworkFailure();

      final result = await world.delete()((uid: 'u1', entry: entry));

      expect(result.failureOrNull, isA<NetworkFailure>());
      expect(world.store.files, {oldFront: 'local/old'});
    });

    test('the profile weight moves to the remaining latest weight', () async {
      world.profiles.profile = const UserProfile(weightKg: 80);
      world.repository.entries
        ..['e1'] = entry
        ..['old'] = BodyEntry(
          id: 'old',
          date: DateTime(2026, 5, 1),
          weightKg: 84,
        );

      await world.delete()((uid: 'u1', entry: entry));

      expect(world.profiles.profile.weightKg, 84);
    });
  });
}
