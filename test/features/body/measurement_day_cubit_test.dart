import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/body/domain/entry_body_fat.dart';
import 'package:get_workout/features/body/presentation/measurement_day_cubit.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:mocktail/mocktail.dart';

import 'body_fakes.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  const user = AuthUser(id: 'u1', isAnonymous: true);
  final now = DateTime(2026, 11, 12, 9, 30);
  final rev = now.millisecondsSinceEpoch;
  const tracked = {BodyMeasurement.waist, BodyMeasurement.hips};
  const oldFront = 'users/u1/photos/old/front-1.jpg';
  final previous = BodyEntry(
    id: 'old',
    date: DateTime(2026, 10, 1),
    photos: const {PhotoPose.front: oldFront},
  );

  late MockAuthRepository auth;
  late StreamController<AuthUser?> users;
  late BodyPhotoWorld world;

  setUp(() {
    auth = MockAuthRepository();
    users = StreamController<AuthUser?>.broadcast();
    world = BodyPhotoWorld();
    world.repository.entries['old'] = previous;
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
  });

  MeasurementDayCubit build({
    BodyEntry? initial,
    Set<BodyMeasurement> tracked = tracked,
  }) => MeasurementDayCubit(
    setup: (
      initial: initial,
      tracked: tracked,
      weightUnit: WeightUnit.kg,
      lengthUnit: LengthUnit.inch,
      startKg: 82.94,
    ),
    saveEntry: world.save(() => now),
    newEntryId: NewBodyEntryId(world.repository),
    discardCapture: DiscardCapture(world.store),
    watchEntries: WatchBodyEntries(world.repository),
    restorePhoto: RestoreBodyPhoto(world.sync),
    getCurrentUser: GetCurrentUser(auth),
    watchAuthUser: WatchAuthUser(auth),
    clock: () => now,
  );

  /// From the weight to the photos, without entering anything.
  Future<void> toPhotos(MeasurementDayCubit cubit) async {
    while (cubit.state.step != MeasureStep.photos) {
      await cubit.next();
    }
  }

  test('three steps; the ruler starts at the start weight, rounded', () async {
    final cubit = build();

    expect(cubit.state.step, MeasureStep.weight);
    expect(cubit.state.weight, 82.9);
    expect(cubit.state.groups, [
      [BodyMeasurement.waist],
      [BodyMeasurement.hips],
    ]);
    await toPhotos(cubit);
    expect(cubit.state.step, MeasureStep.photos);
    await cubit.close();
  });

  test(
    'loads the ghosts itself, from the backup when not on the device',
    () async {
      world.sync.start(Stream.value((id: 'u1', guest: false)));
      world.backup.remote[oldFront] = 'cloud';
      final cubit = build();
      await pumpEventQueue();

      expect(cubit.state.ghosts, {PhotoPose.front: 'local/$oldFront'});
      await cubit.close();
    },
  );

  test('a full day saves converted values and files its photos', () async {
    final cubit = build()..setWeight(80.5);
    await cubit.next();
    cubit.setMeasurement(BodyMeasurement.waist, '34');
    await cubit.next();
    cubit
      ..openCamera(PhotoPose.front)
      ..photoTaken('/tmp/front.jpg');
    expect(cubit.state.camera, isNull);
    await cubit.next(); // the photos: saves

    expect(cubit.state.status, MeasurementDayStatus.saved);
    final entry = world.repository.entries['id1']!;
    expect(entry.date, now);
    expect(entry.weightKg, 80.5);
    expect(entry.measurements, {BodyMeasurement.waist: 34 * 2.54});
    final front = 'users/u1/photos/id1/front-$rev.jpg';
    expect(entry.photos, {PhotoPose.front: front});
    expect(world.queue.saved.keys, [front]);
    expect(world.store.discarded, ['/tmp/front.jpg']);
    await cubit.close();
  });

  test(
    'the weight cannot be skipped: an untouched ruler saves its value',
    () async {
      final cubit = build();
      await toPhotos(cubit);
      await cubit.next();

      expect(world.repository.entries['id1']!.weightKg, 82.9);
      await cubit.close();
    },
  );

  test('a new day names its id once saved, for its summary; an edited one '
      'does not', () async {
    final cubit = build();
    await toPhotos(cubit);
    expect(cubit.savedNewId, isNull);
    await cubit.next();
    expect(cubit.state.status, MeasurementDayStatus.saved);
    expect(cubit.savedNewId, 'id1');
    await cubit.close();

    final edit = build(initial: world.repository.entries['id1']);
    await toPhotos(edit);
    await edit.next();
    expect(edit.state.status, MeasurementDayStatus.saved);
    expect(edit.savedNewId, isNull);
    await edit.close();
  });

  test('the camera opens on the photos only; Skip and back close it', () async {
    final cubit = build()..openCamera(PhotoPose.left);
    expect(cubit.state.camera, isNull);

    await toPhotos(cubit);
    cubit.openCamera(PhotoPose.left);
    expect(cubit.state.camera, PhotoPose.left);
    cubit.closeCamera();
    expect(cubit.state.camera, isNull);

    cubit.openCamera(PhotoPose.back);
    expect(cubit.back(), isTrue);
    expect(cubit.state.camera, isNull);
    expect(cubit.state.step, MeasureStep.photos);
    await cubit.close();
  });

  test('a retaken picture, and those left, are removed', () async {
    final cubit = build();
    await toPhotos(cubit);
    cubit
      ..openCamera(PhotoPose.front)
      ..photoTaken('/tmp/a.jpg')
      ..openCamera(PhotoPose.front)
      ..photoTaken('/tmp/b.jpg');
    expect(world.store.discarded, ['/tmp/a.jpg']);

    // Without the camera open, a picture has nowhere to go.
    cubit.photoTaken('/tmp/c.jpg');
    expect(world.store.discarded, ['/tmp/a.jpg', '/tmp/c.jpg']);

    await cubit.close();
    expect(world.store.discarded, ['/tmp/a.jpg', '/tmp/c.jpg', '/tmp/b.jpg']);
    expect(world.repository.calls, isEmpty);
  });

  test('out-of-range values keep the measurements until fixed, named then '
      'and kept up to date', () async {
    final cubit = build();
    await cubit.next();
    cubit.setMeasurement(BodyMeasurement.waist, '2');
    expect(cubit.state.invalidMeasurements, isEmpty);

    await cubit.next();
    expect(cubit.state.step, MeasureStep.measurements);
    expect(cubit.state.invalidMeasurements, {BodyMeasurement.waist});

    // The limits shown in inches are accepted.
    cubit.setMeasurement(BodyMeasurement.waist, '3.9');
    expect(cubit.state.invalidMeasurements, isEmpty);
    await cubit.next();
    expect(cubit.state.step, MeasureStep.photos);
    await cubit.close();
  });

  test('the body fat estimate follows the values typed', () async {
    final cubit = build(
      tracked: {BodyMeasurement.neck, BodyMeasurement.abdomen},
    );
    await cubit.next();
    expect(
      cubit.bodyFat(sex: Sex.male, heightCm: 180),
      isA<BodyFatNeedsMeasurements>(),
    );

    cubit
      ..setMeasurement(BodyMeasurement.neck, '15')
      ..setMeasurement(BodyMeasurement.abdomen, '35');

    expect(cubit.bodyFat(sex: Sex.male, heightCm: 180).percent, isNotNull);
    expect(cubit.bodyFat(sex: null, heightCm: 180), isA<BodyFatNeedsSex>());
    await cubit.close();
  });

  test('a failed save retried saves the same entry', () async {
    world.repository.startFailure = const NetworkFailure();
    final cubit = build();
    await toPhotos(cubit);
    await cubit.next();
    expect(cubit.state.status, MeasurementDayStatus.saveFailed);

    world.repository.startFailure = null;
    await cubit.next();

    expect(world.repository.calls, ['add id1', 'add id1']);
    expect(cubit.state.status, MeasurementDayStatus.saved);
    await cubit.close();
  });

  test('has changes once something is entered, until saved', () async {
    final cubit = build();
    expect(cubit.hasChanges, isFalse);

    cubit.setWeight(80);
    expect(cubit.hasChanges, isTrue);

    await toPhotos(cubit);
    await cubit.next();
    expect(cubit.state.status, MeasurementDayStatus.saved);
    expect(cubit.hasChanges, isFalse);
    await cubit.close();
  });

  test('has no changes once closed', () async {
    final cubit = build()..setWeight(80);

    users.add(null);
    await pumpEventQueue();

    expect(cubit.state.status, MeasurementDayStatus.closed);
    expect(cubit.hasChanges, isFalse);
    await cubit.close();
  });

  test('back moves one step, and is false on the first', () async {
    final cubit = build();
    expect(cubit.back(), isFalse);

    await cubit.next();
    expect(cubit.back(), isTrue);
    expect(cubit.state.step, MeasureStep.weight);
    await cubit.close();
  });

  test('a change of the tracked measurements changes the rows', () async {
    final cubit = build();
    await cubit.next();

    cubit.setTracked({BodyMeasurement.neck, BodyMeasurement.hips});

    expect(cubit.state.step, MeasureStep.measurements);
    expect(cubit.state.groups, [
      [BodyMeasurement.neck],
      [BodyMeasurement.hips],
    ]);
    await cubit.close();
  });

  group('pairs', () {
    const thighs = {
      BodyMeasurement.waist,
      BodyMeasurement.leftThigh,
      BodyMeasurement.rightThigh,
      BodyMeasurement.leftCalf,
    };

    test('both sides tracked share a row; one side stays alone', () {
      final cubit = build(tracked: thighs);

      expect(cubit.state.groups, [
        [BodyMeasurement.waist],
        [BodyMeasurement.leftThigh, BodyMeasurement.rightThigh],
        [BodyMeasurement.leftCalf],
      ]);
      unawaited(cubit.close());
    });

    test('both sides are saved; an invalid side is named', () async {
      final cubit = build(tracked: thighs);
      await cubit.next();
      cubit
        ..setMeasurement(BodyMeasurement.leftThigh, '22')
        ..setMeasurement(BodyMeasurement.rightThigh, '200');

      await cubit.next();
      expect(cubit.state.invalidMeasurements, {BodyMeasurement.rightThigh});

      cubit.setMeasurement(BodyMeasurement.rightThigh, '22.5');
      await cubit.next();
      await cubit.next();

      expect(world.repository.entries['id1']!.measurements, {
        BodyMeasurement.leftThigh: 22 * 2.54,
        BodyMeasurement.rightThigh: 22.5 * 2.54,
      });
      await cubit.close();
    });
  });

  group('editing', () {
    const keptBack = 'users/u1/photos/e1/back-1.jpg';
    final initial = BodyEntry(
      id: 'e1',
      date: DateTime(2026, 11, 1),
      weightKg: 80.123,
      measurements: const {
        BodyMeasurement.neck: 38.1,
        BodyMeasurement.waist: 86,
      },
      photos: const {PhotoPose.back: keptBack},
    );

    test('an untouched entry has no changes', () async {
      final cubit = build(initial: initial);
      expect(cubit.hasChanges, isFalse);

      await cubit.next();
      expect(cubit.hasChanges, isFalse);
      await cubit.close();
    });

    test('a moved ruler is a change; moving it back is none', () async {
      final cubit = build(initial: initial);
      final weight = cubit.state.weight;

      cubit.setWeight(81);
      expect(cubit.hasChanges, isTrue);
      cubit.setWeight(weight);
      expect(cubit.hasChanges, isFalse);
      await cubit.close();
    });

    test('clearing a stored measurement is a change, and clears it', () async {
      final cubit = build(initial: initial);
      await cubit.next();
      // The entry's own measurement is a row although not tracked.
      expect(cubit.state.groups.first, [BodyMeasurement.neck]);

      cubit.setMeasurement(BodyMeasurement.neck, '');
      expect(cubit.hasChanges, isTrue);
      await toPhotos(cubit);
      await cubit.next();

      expect(world.repository.entries['e1']!.measurements, {
        BodyMeasurement.waist: 86,
      });
      await cubit.close();
    });

    test(
      "going through unchanged keeps all the entry's values and photos",
      () async {
        final cubit = build(initial: initial);
        await toPhotos(cubit);
        await cubit.next();

        expect(world.repository.calls, ['update e1']);
        final entry = world.repository.entries['e1']!;
        expect(entry.date, initial.date);
        expect(entry.weightKg, 80.123);
        expect(entry.measurements, initial.measurements);
        expect(entry.photos, {PhotoPose.back: keptBack});
        await cubit.close();
      },
    );
  });

  test('closes when the user changes', () async {
    final cubit = build();

    users.add(null);
    await pumpEventQueue();

    expect(cubit.state.status, MeasurementDayStatus.closed);
    await cubit.close();
  });
}
