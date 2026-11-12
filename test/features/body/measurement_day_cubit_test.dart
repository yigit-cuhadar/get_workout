import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/body/presentation/measurement_day_cubit.dart';
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

  Future<void> skipAll(MeasurementDayCubit cubit) async {
    while (!cubit.state.isLast) {
      await cubit.skip();
    }
    await cubit.skip();
  }

  test('steps go weight, tracked measurements in order, four photos', () async {
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
    final cubit = build()..setWeight('80.5');
    await cubit.next();
    cubit.setMeasurement(BodyMeasurement.waist, '34');
    await cubit.next();
    await cubit.skip(); // hips
    cubit.photoTaken('/tmp/front.jpg');
    await cubit.next();
    await cubit.skip();
    await cubit.skip();
    await cubit.skip(); // back, the last: saves

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

  test('a new day names its id once saved, for its summary; an edited one '
      'does not', () async {
    final cubit = build()..setWeight('80');
    await cubit.next();
    expect(cubit.savedNewId, isNull);
    await skipAll(cubit);
    expect(cubit.state.status, MeasurementDayStatus.saved);
    expect(cubit.savedNewId, 'id1');
    await cubit.close();

    final edit = build(initial: world.repository.entries['id1']);
    await skipAll(edit);
    expect(edit.state.status, MeasurementDayStatus.saved);
    expect(edit.savedNewId, isNull);
    await edit.close();
  });

  test('a retaken or skipped picture, and those left, are removed', () async {
    final cubit = build();
    for (var i = 0; i < 3; i++) {
      await cubit.skip();
    }
    cubit
      ..photoTaken('/tmp/a.jpg')
      ..photoTaken('/tmp/b.jpg');
    expect(world.store.discarded, ['/tmp/a.jpg']);

    await cubit.skip();
    expect(world.store.discarded, ['/tmp/a.jpg', '/tmp/b.jpg']);

    cubit.photoTaken('/tmp/c.jpg');
    await cubit.close();
    expect(world.store.discarded, ['/tmp/a.jpg', '/tmp/b.jpg', '/tmp/c.jpg']);
    expect(world.repository.calls, isEmpty);
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

  test('the limits shown in inches are accepted', () async {
    final cubit = build();
    await cubit.skip();
    cubit.setMeasurement(BodyMeasurement.waist, '3.9');

    await cubit.next();

    expect(cubit.state.invalid, isFalse);
    expect(cubit.state.index, 2);
    await cubit.close();
  });

  test('skipping everything saves nothing', () async {
    final cubit = build();
    await skipAll(cubit);

    expect(cubit.state.status, MeasurementDayStatus.empty);
    expect(world.repository.calls, isEmpty);
    await cubit.close();
  });

  test('a failed save retried saves the same entry', () async {
    world.repository.startFailure = const NetworkFailure();
    final cubit = build()..setWeight('80');
    await cubit.next();
    await skipAll(cubit);
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

    cubit.setWeight('80');
    expect(cubit.hasChanges, isTrue);

    await cubit.next();
    await skipAll(cubit);
    expect(cubit.state.status, MeasurementDayStatus.saved);
    expect(cubit.hasChanges, isFalse);
    await cubit.close();
  });

  test('has no changes once closed', () async {
    final cubit = build()..setWeight('80');

    users.add(null);
    await pumpEventQueue();

    expect(cubit.state.status, MeasurementDayStatus.closed);
    expect(cubit.hasChanges, isFalse);
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

  group('pairs', () {
    const thighs = {
      BodyMeasurement.waist,
      BodyMeasurement.leftThigh,
      BodyMeasurement.rightThigh,
      BodyMeasurement.leftCalf,
    };

    test('both sides tracked share a step; one side stays alone', () async {
      final cubit = build(tracked: thighs);

      expect(cubit.state.steps.take(4), const [
        WeightStep(),
        MeasurementStep(BodyMeasurement.waist),
        PairStep(BodyMeasurement.leftThigh, BodyMeasurement.rightThigh),
        MeasurementStep(BodyMeasurement.leftCalf),
      ]);
      expect(cubit.state.steps, hasLength(8));
      await cubit.close();
    });

    test('Next saves both sides; an invalid side is named', () async {
      final cubit = build(tracked: thighs);
      await cubit.skip();
      await cubit.skip(); // on the thighs
      cubit
        ..setMeasurement(BodyMeasurement.leftThigh, '22')
        ..setMeasurement(BodyMeasurement.rightThigh, '200')
        // Not on this step: ignored.
        ..setMeasurement(BodyMeasurement.waist, '30');

      await cubit.next();
      expect(cubit.state.index, 2);
      expect(cubit.state.invalid, isTrue);
      expect(cubit.state.invalidMeasurements, {BodyMeasurement.rightThigh});

      cubit.setMeasurement(BodyMeasurement.rightThigh, '22.5');
      expect(cubit.state.invalidMeasurements, isEmpty);
      await cubit.next();
      expect(cubit.state.index, 3);
      await skipAll(cubit);

      expect(world.repository.entries['id1']!.measurements, {
        BodyMeasurement.leftThigh: 22 * 2.54,
        BodyMeasurement.rightThigh: 22.5 * 2.54,
      });
      await cubit.close();
    });

    test('a side gained or lost keeps the flow on that measurement', () async {
      final cubit = build(tracked: thighs);
      await cubit.skip();
      await cubit.skip(); // on the thighs

      cubit.setTracked({BodyMeasurement.waist, BodyMeasurement.rightThigh});
      expect(
        cubit.state.step,
        const MeasurementStep(BodyMeasurement.rightThigh),
      );

      cubit.setTracked(thighs);
      expect(
        cubit.state.step,
        const PairStep(BodyMeasurement.leftThigh, BodyMeasurement.rightThigh),
      );
      await cubit.close();
    });

    group('editing', () {
      final initial = BodyEntry(
        id: 'e1',
        date: DateTime(2026, 11, 1),
        measurements: const {
          BodyMeasurement.leftUpperArm: 33,
          BodyMeasurement.rightUpperArm: 34,
        },
      );

      Future<MeasurementDayCubit> onArms() async {
        // Upper arms are not tracked: the entry's own sides make the step.
        final cubit = build(initial: initial);
        while (cubit.state.step is! PairStep) {
          await cubit.skip();
        }
        return cubit;
      }

      test('skipping a pair keeps both stored sides', () async {
        final cubit = await onArms();
        cubit.setMeasurement(BodyMeasurement.leftUpperArm, '20');

        await skipAll(cubit);

        expect(
          world.repository.entries['e1']!.measurements,
          initial.measurements,
        );
        await cubit.close();
      });

      test('an emptied side with Next clears only that side', () async {
        final cubit = await onArms();
        cubit.setMeasurement(BodyMeasurement.rightUpperArm, '');

        await cubit.next();
        await skipAll(cubit);

        expect(world.repository.entries['e1']!.measurements, {
          BodyMeasurement.leftUpperArm: 33,
        });
        await cubit.close();
      });
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

    test(
      "skipping every step keeps all the entry's values and photos",
      () async {
        final cubit = build(initial: initial);
        // The entry's own measurement is a step although not tracked.
        expect(
          cubit.state.steps,
          contains(const MeasurementStep(BodyMeasurement.neck)),
        );

        await skipAll(cubit);

        expect(world.repository.calls, ['update e1']);
        final entry = world.repository.entries['e1']!;
        expect(entry.date, initial.date);
        expect(entry.weightKg, 80.123);
        expect(entry.measurements, initial.measurements);
        expect(entry.photos, {PhotoPose.back: keptBack});
        await cubit.close();
      },
    );

    test(
      'a value typed and then skipped is dropped for the stored one',
      () async {
        final cubit = build(initial: initial)..setWeight('95');

        await skipAll(cubit);

        expect(world.repository.entries['e1']!.weightKg, 80.123);
        await cubit.close();
      },
    );

    test('an emptied field with Next clears the value', () async {
      final cubit = build(initial: initial)..setWeight('');
      await cubit.next();
      while (!cubit.state.isLast) {
        await cubit.skip();
      }
      await cubit.skip();

      final entry = world.repository.entries['e1']!;
      expect(entry.weightKg, isNull);
      expect(entry.measurements, initial.measurements);
      await cubit.close();
    });
  });

  test('closes when the user changes', () async {
    final cubit = build();

    users.add(null);
    await pumpEventQueue();

    expect(cubit.state.status, MeasurementDayStatus.closed);
    await cubit.close();
  });
}
