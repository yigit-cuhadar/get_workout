import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_photo_sync.dart';
import 'package:get_workout/features/body/domain/body_repository.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/body/presentation/measurement_day_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:mocktail/mocktail.dart';

import 'body_fakes.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBodyRepository extends Mock implements BodyRepository {}

void main() {
  const user = AuthUser(id: 'u1', isAnonymous: true);
  final now = DateTime(2026, 11, 12, 9, 30);
  const tracked = {BodyMeasurement.waist, BodyMeasurement.hips};
  const oldFront = 'users/u1/photos/old/front.jpg';
  final previous = BodyEntry(
    id: 'old',
    date: DateTime(2026, 10, 1),
    photos: const {PhotoPose.front: oldFront},
  );

  late MockAuthRepository auth;
  late MockBodyRepository repository;
  late FakePhotoStore store;
  late FakeBackupQueue queue;
  late StreamController<AuthUser?> users;
  late BodyPhotoSync sync;

  setUpAll(() {
    registerFallbackValue(BodyEntry(id: 'x', date: DateTime(2026)));
  });

  setUp(() {
    auth = MockAuthRepository();
    repository = MockBodyRepository();
    store = FakePhotoStore();
    queue = FakeBackupQueue();
    users = StreamController<AuthUser?>.broadcast();
    sync = BodyPhotoSync(queue, store, FakeBackup());
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => repository.newEntryId(any())).thenReturn('day');
    when(() => repository.addEntry(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => repository.updateEntry(any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  MeasurementDayCubit build({BodyEntry? initial}) => MeasurementDayCubit(
    setup: (
      initial: initial,
      entries: [previous],
      tracked: tracked,
      weightUnit: WeightUnit.kg,
      lengthUnit: LengthUnit.inch,
    ),
    saveEntry: SaveBodyEntry(repository, store, sync, clock: () => now),
    newEntryId: NewBodyEntryId(repository),
    restorePhoto: RestoreBodyPhoto(sync),
    getCurrentUser: GetCurrentUser(auth),
    watchAuthUser: WatchAuthUser(auth),
    clock: () => now,
  );

  BodyEntry saved() =>
      verify(() => repository.addEntry('u1', captureAny())).captured.single
          as BodyEntry;

  test('steps go weight, tracked measurements in order, four photos', () {
    final cubit = build();

    expect(cubit.state.steps, const [
      WeightStep(),
      MeasurementStep(BodyMeasurement.waist),
      MeasurementStep(BodyMeasurement.hips),
      PhotoStep(PhotoPose.front),
      PhotoStep(PhotoPose.right),
      PhotoStep(PhotoPose.left),
      PhotoStep(PhotoPose.back),
    ]);
    unawaited(cubit.close());
  });

  test('the previous photo of a pose on the device is its ghost', () async {
    store.files[oldFront] = 'local/old-front';
    final cubit = build();
    await pumpEventQueue();

    expect(cubit.state.ghosts, {PhotoPose.front: 'local/old-front'});
    await cubit.close();
  });

  test('a full day saves converted values and files its photos', () async {
    final cubit = build()..setWeight('80.5');
    await cubit.next();
    cubit.setMeasurement('34');
    await cubit.next();
    await cubit.skip(); // hips
    cubit.photoTaken('/tmp/front.jpg');
    await cubit.next();
    await cubit.skip();
    await cubit.skip();
    await cubit.skip(); // back, the last: saves

    expect(cubit.state.status, MeasurementDayStatus.saved);
    final entry = saved();
    expect(entry.id, 'day');
    expect(entry.date, now);
    expect(entry.weightKg, 80.5);
    expect(entry.measurements, {BodyMeasurement.waist: 34 * 2.54});
    expect(entry.photos, {PhotoPose.front: 'users/u1/photos/day/front.jpg'});
    expect(queue.saved.keys, ['users/u1/photos/day/front.jpg']);
    await cubit.close();
  });

  test(
    'an out-of-range value stays on its step until fixed or skipped',
    () async {
      final cubit = build()..setWeight('900');

      await cubit.next();
      expect(cubit.state.index, 0);
      expect(cubit.state.invalid, isTrue);

      await cubit.skip();
      expect(cubit.state.index, 1);
      expect(cubit.state.weight, '');
      await cubit.close();
    },
  );

  test('skipping everything saves nothing', () async {
    final cubit = build();
    for (var i = 0; i < 7; i++) {
      await cubit.skip();
    }

    expect(cubit.state.status, MeasurementDayStatus.empty);
    verifyNever(() => repository.addEntry(any(), any()));
    await cubit.close();
  });

  test('back moves one step, and is false on the first', () async {
    final cubit = build();
    expect(cubit.back(), isFalse);

    await cubit.skip();
    expect(cubit.back(), isTrue);
    expect(cubit.state.index, 0);
    await cubit.close();
  });

  test('changing the tracked measurements keeps the current step', () async {
    final cubit = build();
    await cubit.skip();
    await cubit.skip(); // on hips

    cubit.setTracked({BodyMeasurement.neck, BodyMeasurement.hips});

    expect(cubit.state.step, const MeasurementStep(BodyMeasurement.hips));
    expect(cubit.state.steps[1], const MeasurementStep(BodyMeasurement.neck));
    await cubit.close();
  });

  test('an edit keeps its date, untouched values and kept photos', () async {
    const keptBack = 'users/u1/photos/e1/back.jpg';
    final initial = BodyEntry(
      id: 'e1',
      date: DateTime(2026, 11, 1),
      weightKg: 80.123,
      measurements: const {BodyMeasurement.neck: 38.1},
      photos: const {PhotoPose.back: keptBack},
    );
    final cubit = build(initial: initial);
    // The entry's own measurement is a step although not tracked.
    expect(
      cubit.state.steps,
      contains(const MeasurementStep(BodyMeasurement.neck)),
    );

    while (!cubit.state.isLast) {
      await cubit.next();
    }
    await cubit.next();

    final entry =
        verify(() => repository.updateEntry('u1', captureAny())).captured.single
            as BodyEntry;
    expect(entry.date, initial.date);
    expect(entry.weightKg, 80.123);
    expect(entry.measurements, {BodyMeasurement.neck: 38.1});
    expect(entry.photos, {PhotoPose.back: keptBack});
    await cubit.close();
  });

  test('closes when the user changes', () async {
    final cubit = build();

    users.add(null);
    await pumpEventQueue();

    expect(cubit.state.status, MeasurementDayStatus.closed);
    await cubit.close();
  });
}
