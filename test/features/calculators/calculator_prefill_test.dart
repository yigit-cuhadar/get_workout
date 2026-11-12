import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';
import 'package:get_workout/features/calculators/domain/calculators_usecases.dart';
import 'package:get_workout/features/calculators/domain/calories.dart';
import 'package:get_workout/features/calculators/domain/known_body_values.dart';
import 'package:get_workout/features/calculators/presentation/body_fat_cubit.dart';
import 'package:get_workout/features/calculators/presentation/body_indices_cubit.dart';
import 'package:get_workout/features/calculators/presentation/calculator_input.dart';
import 'package:get_workout/features/calculators/presentation/calories_cubit.dart';
import 'package:get_workout/features/calculators/presentation/macros_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

import 'known_values_fakes.dart';

final weighed = DateTime(2026, 11, 11);
final measured = DateTime(2026, 11, 3);

final everything = KnownBodyValues(
  sex: Sex.male,
  ageYears: 36,
  heightCm: 180,
  weightKg: 80.4,
  weightDate: weighed,
  neckCm: 39,
  neckDate: measured,
  waistCm: 84.5,
  waistDate: measured,
  hipCm: 98,
  hipDate: measured,
  bodyFatPercent: 15.24,
  bodyFatDate: measured,
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

      expect(
        cubit.state,
        const CaloriesState(
          height: '172',
          known: {CalculatorInput.height: KnownInput()},
        ),
      );
    });

    test('known inputs show as known, dated when from the body log; sex '
        'and activity stay plain selections', () async {
      final cubit = build();

      await arrive(everything);

      expect(cubit.state.known, {
        CalculatorInput.bodyWeight: KnownInput(weighed),
        CalculatorInput.height: const KnownInput(),
        CalculatorInput.age: const KnownInput(),
      });
    });

    test('editing a known input keeps its value and result but makes it '
        'a plain field', () async {
      final cubit = build();
      await arrive(everything);
      final result = cubit.state.result;

      cubit.editKnown(CalculatorInput.bodyWeight);

      expect(cubit.state.weight, '80.4');
      expect(cubit.state.result, result);
      expect(cubit.state.known.keys, [
        CalculatorInput.height,
        CalculatorInput.age,
      ]);

      cubit.weightChanged('');
      expect(cubit.state.weight, '');
      expect(cubit.state.known, isNot(contains(CalculatorInput.bodyWeight)));
    });

    test('an input changed before the values arrived is not known', () async {
      final cubit = build()..ageChanged('40');

      await arrive(everything);

      expect(cubit.state.known, isNot(contains(CalculatorInput.age)));
      expect(cubit.state.known, contains(CalculatorInput.height));
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
      expect(cubit.state.known, isNot(contains(CalculatorInput.waist)));
    });

    test('known circumferences carry their date, the height none', () async {
      final cubit = build();

      await arrive(everything);

      expect(cubit.state.known, {
        CalculatorInput.height: const KnownInput(),
        CalculatorInput.neck: KnownInput(measured),
        CalculatorInput.waist: KnownInput(measured),
        CalculatorInput.hip: KnownInput(measured),
      });

      cubit.editKnown(CalculatorInput.neck);
      expect(cubit.state.known, isNot(contains(CalculatorInput.neck)));
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
      expect(cubit.state.known.keys, [
        CalculatorInput.bodyWeight,
        CalculatorInput.height,
      ]);
    });

    test('the known body fat carries its date', () async {
      final cubit = build()..weightChanged('75');

      await arrive(everything);

      expect(cubit.state.known, {
        CalculatorInput.height: const KnownInput(),
        CalculatorInput.bodyFat: KnownInput(measured),
      });

      cubit.editKnown(CalculatorInput.bodyFat);
      expect(cubit.state.known.keys, [CalculatorInput.height]);
      expect(cubit.state.bodyFat, '15.2');
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
      expect(cubit.state.known, {
        CalculatorInput.bodyWeight: KnownInput(weighed),
      });

      cubit.editKnown(CalculatorInput.bodyWeight);
      expect(cubit.state.known, isEmpty);
      expect(cubit.state.weight, '80.4');
    });

    test('a weight the user changed first stays', () async {
      final cubit = build()..weightChanged('75');

      await arrive(everything);

      expect(cubit.state.weight, '75');
      expect(cubit.state.known, isEmpty);
    });

    test('an unknown weight stays empty', () async {
      final cubit = build()..caloriesChanged('2500');

      await arrive(const KnownBodyValues());

      expect(cubit.state.weight, '');
      expect(cubit.state.calories, '2500');
      expect(cubit.state.known, isEmpty);
    });
  });
}
