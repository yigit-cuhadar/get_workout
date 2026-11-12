import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/settings/data/firestore_settings_repository.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

void main() {
  const defaults = UserSettings(
    weightUnit: WeightUnit.lb,
    lengthUnit: LengthUnit.inch,
  );
  final standardMeasurements = [
    for (final measurement in BodyMeasurement.standard) measurement.code,
  ];
  late FakeFirebaseFirestore firestore;
  late FirestoreSettingsRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreSettingsRepository(firestore, defaults: defaults);
  });

  DocumentReference<Map<String, dynamic>> user() =>
      firestore.collection('users').doc('u1');

  test('a missing document gives the defaults', () async {
    expect(await repository.watchSettings('u1').first, defaults);
  });

  test('a document without a settings map gives the defaults', () async {
    await user().set({'favoriteExerciseIds': <String>[]});
    expect(await repository.watchSettings('u1').first, defaults);
  });

  test('missing or unknown codes fall back to the defaults', () async {
    await user().set({
      'settings': {'weightUnit': 'kg', 'lengthUnit': 'furlong'},
    });
    expect(
      await repository.watchSettings('u1').first,
      defaults.copyWith(weightUnit: WeightUnit.kg),
    );
  });

  test('the effort scale reads its codes, off when unknown', () async {
    await user().set({
      'settings': {'effortScale': 'rir'},
    });
    expect(
      (await repository.watchSettings('u1').first).effortScale,
      EffortScale.rir,
    );
    await user().set({
      'settings': {'effortScale': 'borg'},
    });
    expect(
      (await repository.watchSettings('u1').first).effortScale,
      EffortScale.off,
    );
  });

  test('save writes the settings map with stored codes', () async {
    const settings = UserSettings(
      weightUnit: WeightUnit.kg,
      lengthUnit: LengthUnit.inch,
      themePreference: ThemePreference.dark,
      effortScale: EffortScale.rpe,
    );

    final result = await repository.saveSettings('u1', settings);

    expect(result.isOk, isTrue);
    expect((await user().get()).data(), {
      'settings': {
        'weightUnit': 'kg',
        'lengthUnit': 'in',
        'themeMode': 'dark',
        'effortScale': 'rpe',
        'restTimer': {'enabled': true, 'defaultS': 90},
        'stepGoal': 10000,
        'trackedMeasurements': standardMeasurements,
      },
    });
    expect(await repository.watchSettings('u1').first, settings);
  });

  group('rest timer', () {
    test('is stored and read back', () async {
      final settings = defaults.copyWith(
        restTimer: const RestTimerSettings(
          enabled: false,
          defaultS: 120,
          notify: true,
        ),
      );

      await repository.saveSettings('u1', settings);

      final stored = (await user().get()).data()!['settings'] as Map;
      expect(stored['restTimer'], {
        'enabled': false,
        'defaultS': 120,
        'notify': true,
      });
      expect(await repository.watchSettings('u1').first, settings);
    });

    test('missing or malformed values read as the defaults', () async {
      await user().set({
        'settings': {
          'restTimer': {'enabled': 'yes', 'defaultS': 'long', 'notify': 1},
        },
      });
      expect(
        (await repository.watchSettings('u1').first).restTimer,
        const RestTimerSettings(),
      );
      await user().set({
        'settings': {'restTimer': true},
      });
      expect(
        (await repository.watchSettings('u1').first).restTimer,
        const RestTimerSettings(),
      );
    });

    test('a duration outside the limits is clamped', () async {
      await user().set({
        'settings': {
          'restTimer': {'defaultS': 5000},
        },
      });
      expect(
        (await repository.watchSettings('u1').first).restTimer.defaultS,
        RestTimerSettings.maxS,
      );
      await user().set({
        'settings': {
          'restTimer': {'defaultS': 2.4},
        },
      });
      expect(
        (await repository.watchSettings('u1').first).restTimer.defaultS,
        RestTimerSettings.minS,
      );
    });
  });

  group('step goal', () {
    test('is stored and read back', () async {
      final settings = defaults.copyWith(stepGoal: 7500);

      await repository.saveSettings('u1', settings);

      final stored = (await user().get()).data()!['settings'] as Map;
      expect(stored['stepGoal'], 7500);
      expect(await repository.watchSettings('u1').first, settings);
    });

    test('a missing or malformed goal reads as the default', () async {
      await user().set({
        'settings': {'stepGoal': 'many'},
      });
      expect(
        (await repository.watchSettings('u1').first).stepGoal,
        StepGoal.standard,
      );
    });

    test('a goal outside the limits is clamped and rounded', () async {
      await user().set({
        'settings': {'stepGoal': 999999},
      });
      expect(
        (await repository.watchSettings('u1').first).stepGoal,
        StepGoal.max,
      );
      await user().set({
        'settings': {'stepGoal': 12.0},
      });
      expect(
        (await repository.watchSettings('u1').first).stepGoal,
        StepGoal.min,
      );
      await user().set({
        'settings': {'stepGoal': 8000.4},
      });
      expect((await repository.watchSettings('u1').first).stepGoal, 8000);
    });
  });

  group('tracked measurements', () {
    test('are stored as codes and read back', () async {
      final settings = defaults.copyWith(
        trackedMeasurements: {BodyMeasurement.neck, BodyMeasurement.leftCalf},
      );

      await repository.saveSettings('u1', settings);

      final stored = (await user().get()).data()!['settings'] as Map;
      expect(stored['trackedMeasurements'], ['neck', 'leftCalf']);
      expect(await repository.watchSettings('u1').first, settings);
    });

    test('none tracked stays none', () async {
      final settings = defaults.copyWith(trackedMeasurements: {});

      await repository.saveSettings('u1', settings);

      expect(
        (await repository.watchSettings('u1').first).trackedMeasurements,
        isEmpty,
      );
    });

    test('missing reads as the default, unknown codes are dropped', () async {
      await user().set({'settings': <String, Object?>{}});
      expect(
        (await repository.watchSettings('u1').first).trackedMeasurements,
        BodyMeasurement.standard,
      );
      await user().set({
        'settings': {
          'trackedMeasurements': ['waist', 'wingspan', 3],
        },
      });
      expect((await repository.watchSettings('u1').first).trackedMeasurements, {
        BodyMeasurement.waist,
      });
    });
  });

  test('save keeps the other fields of the user document', () async {
    await user().set({
      'profile': {'goal': 'get_stronger'},
      'settings': {'reminderTimes': true, 'weightUnit': 'lb'},
    });

    await repository.saveSettings(
      'u1',
      defaults.copyWith(weightUnit: WeightUnit.kg),
    );

    expect((await user().get()).data(), {
      'profile': {'goal': 'get_stronger'},
      'settings': {
        'reminderTimes': true,
        'weightUnit': 'kg',
        'lengthUnit': 'in',
        'themeMode': 'system',
        'effortScale': 'off',
        'restTimer': {'enabled': true, 'defaultS': 90},
        'stepGoal': 10000,
        'trackedMeasurements': standardMeasurements,
      },
    });
  });

  test('the stream emits every change', () async {
    final light = defaults.copyWith(themePreference: ThemePreference.light);
    final emitted = repository.watchSettings('u1');
    final expectation = expectLater(emitted, emitsInOrder([defaults, light]));

    await repository.saveSettings('u1', light);

    await expectation;
  });

  group('bar and plates', () {
    const plates = [
      Plate(weightKg: 20, pairs: 2),
      Plate(weightKg: 1.25, pairs: 1),
    ];
    final custom = defaults.copyWith(
      customBarWeightKg: 15,
      customPlates: plates,
    );

    test('custom equipment is stored and read back', () async {
      await repository.saveSettings('u1', custom);

      final stored = (await user().get()).data()!['settings'] as Map;
      expect(stored['barWeightKg'], 15);
      expect(stored['plates'], [
        {'weightKg': 20, 'pairs': 2},
        {'weightKg': 1.25, 'pairs': 1},
      ]);
      expect(await repository.watchSettings('u1').first, custom);
    });

    test(
      'standard equipment is not stored, and clears custom equipment',
      () async {
        await repository.saveSettings('u1', custom);

        await repository.saveSettings('u1', custom.withStandardEquipment());

        final stored = (await user().get()).data()!['settings'] as Map;
        expect(stored.containsKey('barWeightKg'), isFalse);
        expect(stored.containsKey('plates'), isFalse);
        expect(
          await repository.watchSettings('u1').first,
          custom.withStandardEquipment(),
        );
      },
    );

    test('saving equipment keeps the other fields', () async {
      await user().set({
        'profile': {'goal': 'get_stronger'},
        'settings': {'reminderTimes': true, 'weightUnit': 'kg'},
      });

      await repository.saveSettings('u1', custom);

      final data = (await user().get()).data()!;
      expect(data['profile'], {'goal': 'get_stronger'});
      expect((data['settings'] as Map)['reminderTimes'], true);
      expect((data['settings'] as Map)['barWeightKg'], 15);
    });

    test('malformed equipment falls back or is skipped', () async {
      await user().set({
        'settings': {
          'barWeightKg': 'heavy',
          'plates': [
            {'weightKg': 10, 'pairs': 2},
            {'weightKg': -5, 'pairs': 1},
            {'weightKg': 5, 'pairs': 1.5},
            'plate',
          ],
        },
      });

      final settings = await repository.watchSettings('u1').first;

      expect(settings.customBarWeightKg, isNull);
      expect(
        settings.barWeightKg,
        UserSettings.defaultBarWeightKg(WeightUnit.lb),
      );
      expect(settings.plates, const [Plate(weightKg: 10, pairs: 2)]);
    });

    test('stored equipment beyond the limits is clamped', () async {
      await user().set({
        'settings': {
          'barWeightKg': 250,
          'plates': [
            {'weightKg': 0.05, 'pairs': 1},
            {'weightKg': 150, 'pairs': 30},
            {'weightKg': 10, 'pairs': -2},
            for (var i = 1; i <= 12; i++) {'weightKg': 20 + i, 'pairs': 1},
          ],
        },
      });

      final settings = await repository.watchSettings('u1').first;

      expect(settings.barWeightKg, maxBarWeightKg);
      expect(settings.plates, hasLength(maxPlateSizes));
      expect(
        settings.plates.first,
        const Plate(weightKg: maxPlateWeightKg, pairs: maxPlatePairs),
      );
      // The 12 largest win; 21 kg, 10 kg and the clamped 0.1 kg are dropped.
      expect(settings.plates.last, const Plate(weightKg: 22, pairs: 1));
    });
  });
}
