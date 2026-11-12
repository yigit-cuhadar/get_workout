import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_photo_sync.dart';
import 'package:get_workout/features/body/domain/body_photos.dart';
import 'package:get_workout/features/body/domain/body_repository.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:mocktail/mocktail.dart';

import 'body_fakes.dart';

class MockBodyRepository extends Mock implements BodyRepository {}

void main() {
  final now = DateTime(2026, 11, 12, 9);
  const kept = 'users/u1/photos/e1/front.jpg';
  const newBack = 'users/u1/photos/e1/back.jpg';

  late MockBodyRepository repository;
  late FakePhotoStore store;
  late FakeBackupQueue queue;
  late BodyPhotoSync sync;

  setUpAll(() {
    registerFallbackValue(BodyEntry(id: 'x', date: DateTime(2026)));
  });

  setUp(() {
    repository = MockBodyRepository();
    store = FakePhotoStore();
    queue = FakeBackupQueue();
    sync = BodyPhotoSync(queue, store, FakeBackup());
    when(() => repository.addEntry(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => repository.updateEntry(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => repository.deleteEntry(any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  SaveBodyEntry save() =>
      SaveBodyEntry(repository, store, sync, clock: () => now);

  group('save', () {
    test('files new photos, queues their backup, then stores the entry '
        'naming them', () async {
      final entry = BodyEntry(
        id: 'e1',
        date: now,
        weightKg: 80,
        photos: const {PhotoPose.front: kept},
      );

      final result = await save()((
        uid: 'u1',
        entry: entry,
        newPhotos: {PhotoPose.back: '/tmp/shot.jpg'},
        isNew: false,
      ));

      expect(result.isOk, isTrue);
      expect(store.files, {newBack: 'local/$newBack'});
      expect(queue.saved, {newBack: BackupTask.upload});
      final stored =
          verify(() => repository.updateEntry('u1', captureAny()))
                  .captured
                  .single
              as BodyEntry;
      expect(stored.photos, {PhotoPose.front: kept, PhotoPose.back: newBack});
      verifyNever(() => repository.addEntry(any(), any()));
    });

    test('a new entry is added', () async {
      final entry = BodyEntry(id: 'w1', date: now, weightKg: 80);

      await save()((uid: 'u1', entry: entry, newPhotos: {}, isNew: true));

      verify(() => repository.addEntry('u1', entry)).called(1);
    });

    test('an invalid entry writes nothing', () async {
      final entry = BodyEntry(id: 'w1', date: now, weightKg: 500);

      final result = await save()((
        uid: 'u1',
        entry: entry,
        newPhotos: {PhotoPose.front: '/tmp/shot.jpg'},
        isNew: true,
      ));

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(store.files, isEmpty);
      verifyNever(() => repository.addEntry(any(), any()));
    });

    test(
      'a photo that cannot be filed fails before the entry is stored',
      () async {
        store.failSave = true;

        final result = await save()((
          uid: 'u1',
          entry: BodyEntry(id: 'e1', date: now),
          newPhotos: {PhotoPose.front: '/tmp/shot.jpg'},
          isNew: true,
        ));

        expect(result.isOk, isFalse);
        expect(queue.saved, isEmpty);
        verifyNever(() => repository.addEntry(any(), any()));
      },
    );
  });

  group('delete', () {
    final entry = BodyEntry(
      id: 'e1',
      date: now,
      photos: const {PhotoPose.front: kept},
    );

    test(
      'removes the entry, its photos, and queues their backup removal',
      () async {
        store.files[kept] = 'local/$kept';

        final result = await DeleteBodyEntry(repository, store, sync)((
          uid: 'u1',
          entry: entry,
        ));

        expect(result.isOk, isTrue);
        verify(() => repository.deleteEntry('u1', 'e1')).called(1);
        expect(store.files, isEmpty);
        expect(queue.saved, {kept: BackupTask.delete});
      },
    );

    test('keeps the photos when the entry could not be deleted', () async {
      store.files[kept] = 'local/$kept';
      when(() => repository.deleteEntry(any(), any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));

      final result = await DeleteBodyEntry(repository, store, sync)((
        uid: 'u1',
        entry: entry,
      ));

      expect(result.failureOrNull, isA<NetworkFailure>());
      expect(store.files, {kept: 'local/$kept'});
      expect(queue.saved, isEmpty);
    });
  });
}
