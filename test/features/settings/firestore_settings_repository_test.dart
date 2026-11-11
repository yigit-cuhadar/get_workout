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
}
