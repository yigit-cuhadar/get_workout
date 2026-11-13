import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/domain/body_chart.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
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

  test('the effort scale reads its codes, by feel when unknown', () async {
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
      EffortScale.byFeel,
    );
  });

  test('the effort scale "off" of older versions reads as by feel', () async {
    // Other defaults, so by feel can only come from the stored code.
    final rpeByDefault = FirestoreSettingsRepository(
      firestore,
      defaults: defaults.copyWith(effortScale: EffortScale.rpe),
    );
    for (final code in ['off', 'feel']) {
      await user().set({
        'settings': {'effortScale': code},
      });
      expect(
        (await rpeByDefault.watchSettings('u1').first).effortScale,
        EffortScale.byFeel,
      );
    }
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
        'warmups': {
          'scheme': 'standard',
          'custom': <Object?>[],
          'scope': 'every',
        },
        'autoWarmups': true,
        'stepGoal': 10000,
        'reminders': {
          'workout': {'enabled': false, 'minute': 480},
          'measurement': {'enabled': false, 'everyWeeks': 4, 'minute': 540},
        },
      },
    });
    expect(await repository.watchSettings('u1').first, settings);
  });

  group('reminders', () {
    test('are stored and read back', () async {
      final settings = defaults.copyWith(
        workoutReminder: const WorkoutReminderSettings(
          enabled: true,
          minute: 1110,
        ),
        measurementReminder: MeasurementReminderSettings(
          enabled: true,
          everyWeeks: 2,
          from: CalendarDate(2026, 11, 15),
          minute: 600,
        ),
      );

      await repository.saveSettings('u1', settings);

      final stored = (await user().get()).data()!['settings'] as Map;
      expect(stored['reminders'], {
        'workout': {'enabled': true, 'minute': 1110},
        'measurement': {
          'enabled': true,
          'everyWeeks': 2,
          'from': '2026-11-15',
          'minute': 600,
        },
      });
      expect(await repository.watchSettings('u1').first, settings);
    });

    test('missing or malformed values read as the defaults', () async {
      await user().set({
        'settings': {
          'reminders': {
            'workout': {'enabled': 'yes', 'minute': 'noon'},
            'measurement': {'enabled': 1, 'everyWeeks': 'often', 'from': 'x'},
          },
        },
      });
      final read = await repository.watchSettings('u1').first;
      expect(read.workoutReminder, const WorkoutReminderSettings());
      expect(read.measurementReminder, const MeasurementReminderSettings());
    });

    test('times are clamped and a cadence not offered rounds up', () async {
      await user().set({
        'settings': {
          'reminders': {
            'workout': {'minute': 5000},
            'measurement': {'minute': -3, 'everyWeeks': 3},
          },
        },
      });
      final read = await repository.watchSettings('u1').first;
      expect(read.workoutReminder.minute, ReminderTime.max);
      expect(read.measurementReminder.minute, 0);
      expect(read.measurementReminder.everyWeeks, 4);
    });
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

  group('automatic warm-ups and tips', () {
    test(
      'the scheme, custom sets and scope are stored and read back',
      () async {
        final settings = defaults.copyWith(
          warmups: const WarmupSettings(
            scheme: WarmupScheme.custom,
            custom: [WarmupStep(45, 10), WarmupStep(70, 3)],
            scope: WarmupScope.firstPerMuscle,
          ),
        );

        await repository.saveSettings('u1', settings);

        final stored = (await user().get()).data()!['settings'] as Map;
        expect(stored['warmups'], {
          'scheme': 'custom',
          'custom': [
            {'percent': 45, 'reps': 10},
            {'percent': 70, 'reps': 3},
          ],
          'scope': 'firstPerMuscle',
        });
        // Older app versions read the switch.
        expect(stored['autoWarmups'], true);
        expect(await repository.watchSettings('u1').first, settings);
      },
    );

    test('off is written as the old switch off', () async {
      await repository.saveSettings(
        'u1',
        defaults.copyWith(
          warmups: const WarmupSettings(scheme: WarmupScheme.off),
        ),
      );
      final stored = (await user().get()).data()!['settings'] as Map;
      expect(stored['autoWarmups'], false);
    });

    test('the old switch reads as standard or off', () async {
      await user().set({
        'settings': {'autoWarmups': true},
      });
      expect(
        (await repository.watchSettings('u1').first).warmups,
        const WarmupSettings(),
      );
      await user().set({
        'settings': {'autoWarmups': false},
      });
      expect(
        (await repository.watchSettings('u1').first).warmups.scheme,
        WarmupScheme.off,
      );
    });

    test('the old switch written last by an older version wins', () async {
      await user().set({
        'settings': {
          'warmups': {'scheme': 'full', 'scope': 'every'},
          'autoWarmups': false,
        },
      });
      expect(
        (await repository.watchSettings('u1').first).warmups.scheme,
        WarmupScheme.off,
      );
      await user().set({
        'settings': {
          'warmups': {'scheme': 'off', 'scope': 'firstPerMuscle'},
          'autoWarmups': true,
        },
      });
      final warmups = (await repository.watchSettings('u1').first).warmups;
      expect(warmups.scheme, WarmupScheme.standard);
      expect(warmups.scope, WarmupScope.firstPerMuscle);
    });

    test('malformed custom sets are dropped or clamped', () async {
      await user().set({
        'settings': {
          'warmups': {
            'scheme': 'custom',
            'custom': [
              {'percent': 5, 'reps': 40},
              {'percent': 'half'},
              for (var i = 0; i < 6; i++) {'percent': 60, 'reps': 3},
            ],
            'scope': 'nearby',
          },
        },
      });
      final warmups = (await repository.watchSettings('u1').first).warmups;
      expect(warmups.custom.first, const WarmupStep(10, 20));
      expect(warmups.custom, hasLength(WarmupLimits.maxSets));
      expect(warmups.scope, WarmupScope.every);
    });

    test('custom without sets reads as standard', () async {
      await user().set({
        'settings': {
          'warmups': {'scheme': 'custom', 'custom': <Object?>[]},
        },
      });
      expect(
        (await repository.watchSettings('u1').first).warmups.scheme,
        WarmupScheme.standard,
      );
    });

    test('tips seen are added one by one, others kept', () async {
      await user().set({
        'settings': {
          'seenTips': ['later'],
        },
      });

      await repository.markTipSeen('u1', Tip.effort);
      await repository.markTipSeen('u1', Tip.setTypes);
      await repository.markTipSeen('u1', Tip.effort);
      // A whole save leaves them alone.
      await repository.saveSettings('u1', defaults);

      final stored = (await user().get()).data()!['settings'] as Map;
      expect(stored['seenTips'], ['later', 'effort', 'setTypes']);
      expect((await repository.watchSettings('u1').first).seenTips, {
        Tip.effort,
        Tip.setTypes,
      });
    });

    test('missing ones read as warm-ups on and no tip seen', () async {
      await user().set({
        'settings': {'weightUnit': 'kg'},
      });
      final settings = await repository.watchSettings('u1').first;
      expect(settings.warmups, const WarmupSettings());
      expect(settings.seenTips, isEmpty);
    });

    test('malformed ones read as the defaults, unknown tips dropped', () async {
      await user().set({
        'settings': {
          'autoWarmups': 'no',
          'seenTips': ['setTypes', 'later', 3],
        },
      });
      final settings = await repository.watchSettings('u1').first;
      expect(settings.warmups, const WarmupSettings());
      expect(settings.seenTips, {Tip.setTypes});
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
        customTrackedMeasurements: {
          BodyMeasurement.neck,
          BodyMeasurement.leftCalf,
        },
      );

      await repository.saveSettings('u1', settings);

      final stored = (await user().get()).data()!['settings'] as Map;
      expect(stored['trackedMeasurements'], ['neck', 'leftCalf']);
      expect(await repository.watchSettings('u1').first, settings);
    });

    test('none tracked stays none', () async {
      final settings = defaults.copyWith(customTrackedMeasurements: {});

      await repository.saveSettings('u1', settings);

      expect(
        (await repository.watchSettings('u1').first).customTrackedMeasurements,
        isEmpty,
      );
    });

    test('not chosen is not stored', () async {
      await user().set({
        'settings': {
          'trackedMeasurements': ['neck'],
        },
      });

      await repository.saveSettings('u1', defaults);

      final stored = (await user().get()).data()!['settings'] as Map;
      expect(stored.containsKey('trackedMeasurements'), isFalse);
    });

    test('missing reads as not chosen, unknown codes are dropped', () async {
      await user().set({'settings': <String, Object?>{}});
      expect(
        (await repository.watchSettings('u1').first).customTrackedMeasurements,
        isNull,
      );
      await user().set({
        'settings': {
          'trackedMeasurements': ['waist', 'wingspan', 3],
        },
      });
      expect(
        (await repository.watchSettings('u1').first).customTrackedMeasurements,
        {BodyMeasurement.waist},
      );
    });
  });

  group('body chart', () {
    test('is stored as codes and read back', () async {
      final settings = defaults.copyWith(
        bodyChart: const BodyChartChoice(
          series: [BodySeries.thigh, BodySeries.weeklySets],
          targetLine: false,
        ),
      );

      await repository.saveSettings('u1', settings);

      final stored = (await user().get()).data()!['settings'] as Map;
      expect(stored['bodyChart'], {
        'series': ['thigh', 'weeklySets'],
        'targetLine': false,
      });
      expect(await repository.watchSettings('u1').first, settings);
    });

    test('not chosen is not stored', () async {
      await user().set({
        'settings': {
          'bodyChart': {
            'series': ['weight'],
          },
        },
      });

      await repository.saveSettings('u1', defaults);

      final stored = (await user().get()).data()!['settings'] as Map;
      expect(stored.containsKey('bodyChart'), isFalse);
    });

    test('malformed reads as not chosen, unknown codes are dropped', () async {
      await user().set({
        'settings': {'bodyChart': 'weight'},
      });
      expect((await repository.watchSettings('u1').first).bodyChart, isNull);
      await user().set({
        'settings': {
          'bodyChart': {
            'series': ['waist', 'wingspan', 3],
          },
        },
      });
      expect(
        (await repository.watchSettings('u1').first).bodyChart,
        const BodyChartChoice(series: [BodySeries.waist]),
      );
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
        'effortScale': 'feel',
        'restTimer': {'enabled': true, 'defaultS': 90},
        'warmups': {
          'scheme': 'standard',
          'custom': <Object?>[],
          'scope': 'every',
        },
        'autoWarmups': true,
        'stepGoal': 10000,
        'reminders': {
          'workout': {'enabled': false, 'minute': 480},
          'measurement': {'enabled': false, 'everyWeeks': 4, 'minute': 540},
        },
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
