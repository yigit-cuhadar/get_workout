import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/data/firestore_settings_repository.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

void main() {
  const defaults = UserSettings(
    weightUnit: WeightUnit.lb,
    lengthUnit: LengthUnit.inch,
  );
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

  test('save writes the settings map with stored codes', () async {
    const settings = UserSettings(
      weightUnit: WeightUnit.kg,
      lengthUnit: LengthUnit.inch,
      themePreference: ThemePreference.dark,
    );

    final result = await repository.saveSettings('u1', settings);

    expect(result.isOk, isTrue);
    expect((await user().get()).data(), {
      'settings': {'weightUnit': 'kg', 'lengthUnit': 'in', 'themeMode': 'dark'},
    });
    expect(await repository.watchSettings('u1').first, settings);
  });

  test('save keeps the other fields of the user document', () async {
    await user().set({
      'profile': {'goal': 'get_stronger'},
      'settings': {'effortScale': 'rir', 'weightUnit': 'lb'},
    });

    await repository.saveSettings(
      'u1',
      defaults.copyWith(weightUnit: WeightUnit.kg),
    );

    expect((await user().get()).data(), {
      'profile': {'goal': 'get_stronger'},
      'settings': {
        'effortScale': 'rir',
        'weightUnit': 'kg',
        'lengthUnit': 'in',
        'themeMode': 'system',
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
        'settings': {'effortScale': 'rir', 'weightUnit': 'kg'},
      });

      await repository.saveSettings('u1', custom);

      final data = (await user().get()).data()!;
      expect(data['profile'], {'goal': 'get_stronger'});
      expect((data['settings'] as Map)['effortScale'], 'rir');
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
