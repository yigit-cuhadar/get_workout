import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';
import 'package:get_workout/features/calculators/domain/calculators_usecases.dart';
import 'package:get_workout/features/calculators/domain/calories.dart';
import 'package:get_workout/features/calculators/domain/known_body_values.dart';
import 'package:get_workout/features/calculators/presentation/body_fat_cubit.dart';
import 'package:get_workout/features/calculators/presentation/body_indices_cubit.dart';
import 'package:get_workout/features/calculators/presentation/calories_cubit.dart';
import 'package:get_workout/features/calculators/presentation/macros_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

import 'known_values_fakes.dart';

const everything = KnownBodyValues(
  sex: Sex.male,
  ageYears: 36,
  heightCm: 180,
  weightKg: 80.4,
  neckCm: 39,
  waistCm: 84.5,
  hipCm: 98,
  bodyFatPercent: 15.24,
  activity: ActivityLevel.moderate,
);

void main() {
  late FakeKnownValues known;
  late Completer<KnownBodyValues> arrival;

  setUp(() {
    known = FakeKnownValues();
    arrival = Completer();
    known.answer = arrival.future;
  });

  /// Lets the cubit take the known values.
  Future<void> arrive(KnownBodyValues values) async {
    arrival.complete(values);
    await pumpEventQueue();
  }

  test('a signed-out user asks for nothing and starts empty', () async {
    final cubit = CaloriesCubit(
      const EstimateCalories(),
      signedOut,
      known,
      weightUnit: WeightUnit.kg,
      lengthUnit: LengthUnit.cm,
    );
    await pumpEventQueue();

    expect(known.requests, isEmpty);
    expect(cubit.state, const CaloriesState());
  });

  test('values arriving after the page closed are dropped', () async {
    final cubit = MacrosCubit(
      const SplitMacros(),
      FakeCurrentUser(),
      known,
      weightUnit: WeightUnit.kg,
    );
    await cubit.close();

    await arrive(everything);
  });

  group('CaloriesCubit', () {
    CaloriesCubit build({
      WeightUnit weight = WeightUnit.kg,
      LengthUnit length = LengthUnit.cm,
    }) => CaloriesCubit(
      const EstimateCalories(),
      FakeCurrentUser(),
      known,
      weightUnit: weight,
      lengthUnit: length,
    );

    test('starts from every known input, with the result', () async {
      final cubit = build();
      expect(known.requests, ['u1']);

      await arrive(everything);

      final state = cubit.state;
      expect(state.sex, Sex.male);
      expect(state.activity, ActivityLevel.moderate);
      expect(state.weight, '80.4');
      expect(state.height, '180');
      expect(state.age, '36');
      expect(state.result, isA<Calculated<CalorieEstimate>>());
    });

    test('in the user units', () async {
      final cubit = build(weight: WeightUnit.lb, length: LengthUnit.inch);

      await arrive(everything);

      expect(cubit.state.weight, '177.3');
      expect(cubit.state.height, '70.9');
    });

    test('never overwrites what the user changed first', () async {
      final cubit = build()
        ..sexChanged(Sex.female)
        ..weightChanged('')
        ..ageChanged('40')
        ..activityChanged(ActivityLevel.light);

      await arrive(everything);

      final state = cubit.state;
      expect(state.sex, Sex.female);
      expect(state.activity, ActivityLevel.light);
      expect(state.weight, '');
      expect(state.age, '40');
      expect(state.height, '180');
    });

    test('unknown inputs stay empty', () async {
      final cubit = build();

      await arrive(const KnownBodyValues(heightCm: 172));

      expect(cubit.state, const CaloriesState(height: '172'));
    });
  });

  group('BodyFatCubit', () {
    BodyFatCubit build({LengthUnit length = LengthUnit.cm}) => BodyFatCubit(
      const EstimateBodyFat(),
      FakeCurrentUser(),
      known,
      lengthUnit: length,
    );

    test('starts from sex, height and the circumferences', () async {
      final cubit = build();

      await arrive(everything);

      final state = cubit.state;
      expect(state.sex, Sex.male);
      expect(
        [state.height, state.neck, state.waist, state.hip],
        ['180', '39', '84.5', '98'],
      );
      expect(state.result, isA<Calculated<double>>());
    });

    test('in inches', () async {
      final cubit = build(length: LengthUnit.inch);

      await arrive(everything);

      expect(cubit.state.neck, '15.4');
    });

    test('never overwrites what the user changed first', () async {
      final cubit = build()
        ..waistChanged('90')
        ..sexChanged(Sex.female);

      await arrive(everything);

      expect(cubit.state.waist, '90');
      expect(cubit.state.sex, Sex.female);
      expect(cubit.state.neck, '39');
    });

    test('unknown circumferences stay empty', () async {
      final cubit = build();

      await arrive(const KnownBodyValues(sex: Sex.male, waistCm: 84));

      expect(cubit.state.waist, '84');
      expect(
        [cubit.state.neck, cubit.state.hip, cubit.state.height],
        ['', '', ''],
      );
      expect(cubit.state.result, isNull);
    });
  });

  group('BodyIndicesCubit', () {
    BodyIndicesCubit build() => BodyIndicesCubit(
      const CalculateBodyIndices(),
      FakeCurrentUser(),
      known,
      weightUnit: WeightUnit.kg,
      lengthUnit: LengthUnit.cm,
    );

    test('starts from weight, height and the body fat', () async {
      final cubit = build();

      await arrive(everything);

      expect(cubit.state.weight, '80.4');
      expect(cubit.state.height, '180');
      expect(cubit.state.bodyFat, '15.2');
      final indices = (cubit.state.result! as Calculated).value;
      expect(indices.ffmi, isNotNull);
    });

    test('the body fat the user typed first stays', () async {
      final cubit = build()..bodyFatChanged('20');

      await arrive(everything);

      expect(cubit.state.bodyFat, '20');
      expect(cubit.state.weight, '80.4');
    });

    test('without a known body fat it stays empty', () async {
      final cubit = build();

      await arrive(const KnownBodyValues(weightKg: 80, heightCm: 180));

      expect(cubit.state.bodyFat, '');
      expect(cubit.state.result, isNotNull);
    });
  });

  group('MacrosCubit', () {
    MacrosCubit build() => MacrosCubit(
      const SplitMacros(),
      FakeCurrentUser(),
      known,
      weightUnit: WeightUnit.kg,
    );

    test('starts from the weight; calories stay empty', () async {
      final cubit = build();

      await arrive(everything);

      expect(cubit.state.weight, '80.4');
      expect(cubit.state.calories, '');
    });

    test('a weight the user changed first stays', () async {
      final cubit = build()..weightChanged('75');

      await arrive(everything);

      expect(cubit.state.weight, '75');
    });

    test('an unknown weight stays empty', () async {
      final cubit = build()..caloriesChanged('2500');

      await arrive(const KnownBodyValues());

      expect(cubit.state.weight, '');
      expect(cubit.state.calories, '2500');
    });
  });
}
