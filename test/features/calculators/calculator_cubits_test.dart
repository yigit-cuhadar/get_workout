import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calculators/domain/body_indices.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';
import 'package:get_workout/features/calculators/domain/calculators_usecases.dart';
import 'package:get_workout/features/calculators/domain/calories.dart';
import 'package:get_workout/features/calculators/domain/macros.dart';
import 'package:get_workout/features/calculators/domain/one_rep_max.dart';
import 'package:get_workout/features/calculators/domain/plates.dart';
import 'package:get_workout/features/calculators/presentation/body_fat_cubit.dart';
import 'package:get_workout/features/calculators/presentation/body_indices_cubit.dart';
import 'package:get_workout/features/calculators/presentation/calories_cubit.dart';
import 'package:get_workout/features/calculators/presentation/macros_cubit.dart';
import 'package:get_workout/features/calculators/presentation/one_rep_max_cubit.dart';
import 'package:get_workout/features/calculators/presentation/plates_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

/// The same physical quantities typed in either unit system.
String lb(double kg) => '${WeightUnit.lb.fromKg(kg)}';
String inches(double cm) => '${LengthUnit.inch.fromCm(cm)}';

T valueOf<T>(Calculation<T>? result) => (result! as Calculated<T>).value;

void main() {
  group('CaloriesCubit', () {
    CaloriesCubit build(WeightUnit weight, LengthUnit length) =>
        CaloriesCubit(
            const EstimateCalories(),
            weightUnit: weight,
            lengthUnit: length,
          )
          ..sexChanged(Sex.male)
          ..activityChanged(ActivityLevel.moderate)
          ..ageChanged('30');

    test('lb/in and kg/cm give the same result', () {
      final metric = build(WeightUnit.kg, LengthUnit.cm)
        ..weightChanged('80')
        ..heightChanged('180');
      final imperial = build(WeightUnit.lb, LengthUnit.inch)
        ..weightChanged(lb(80))
        ..heightChanged(inches(180));

      final kg = valueOf(metric.state.result);
      final pounds = valueOf(imperial.state.result);
      expect(kg.bmr, closeTo(1780, 1e-9));
      expect(pounds.bmr, closeTo(kg.bmr, 1e-9));
      expect(pounds.lose.kcal, closeTo(kg.lose.kcal, 1e-9));
    });

    test('no result until every input is filled in', () {
      final cubit =
          CaloriesCubit(
              const EstimateCalories(),
              weightUnit: WeightUnit.kg,
              lengthUnit: LengthUnit.cm,
            )
            ..weightChanged('80')
            ..heightChanged('180')
            ..ageChanged('30');
      expect(cubit.state.result, isNull);
      cubit.sexChanged(Sex.female);
      expect(cubit.state.result, isNull);
      cubit.activityChanged(ActivityLevel.light);
      expect(cubit.state.result, isA<Calculated<CalorieEstimate>>());
      cubit.weightChanged('');
      expect(cubit.state.result, isNull);
      expect(cubit.state.sex, Sex.female);
    });

    test('text that is not a number is out of range', () {
      final cubit = build(WeightUnit.kg, LengthUnit.cm)
        ..weightChanged('80')
        ..heightChanged('abc');
      expect(cubit.state.result, isA<OutOfRange<CalorieEstimate>>());
      expect((cubit.state.result! as OutOfRange).input, CalculatorInput.height);
    });

    test('a decimal comma is accepted', () {
      final cubit = build(WeightUnit.kg, LengthUnit.cm)
        ..weightChanged('80,5')
        ..heightChanged('180');
      expect(valueOf(cubit.state.result).bmr, closeTo(1785, 1e-9));
    });

    test('ranges apply to the converted value', () {
      // 60 lb = 27.2 kg, under the 30 kg minimum.
      final cubit = build(WeightUnit.lb, LengthUnit.inch)
        ..weightChanged('60')
        ..heightChanged('70');
      expect(
        (cubit.state.result! as OutOfRange).input,
        CalculatorInput.bodyWeight,
      );
    });
  });

  group('BodyFatCubit', () {
    test('inches and cm give the same result', () {
      final metric =
          BodyFatCubit(const EstimateBodyFat(), lengthUnit: LengthUnit.cm)
            ..sexChanged(Sex.female)
            ..heightChanged('165')
            ..neckChanged('33')
            ..waistChanged('70')
            ..hipChanged('95');
      final imperial =
          BodyFatCubit(const EstimateBodyFat(), lengthUnit: LengthUnit.inch)
            ..sexChanged(Sex.female)
            ..heightChanged(inches(165))
            ..neckChanged(inches(33))
            ..waistChanged(inches(70))
            ..hipChanged(inches(95));

      expect(valueOf(metric.state.result), closeTo(24.33, 0.01));
      expect(
        valueOf(imperial.state.result),
        closeTo(valueOf(metric.state.result), 1e-9),
      );
    });

    test('the hip is needed for women only', () {
      final cubit =
          BodyFatCubit(const EstimateBodyFat(), lengthUnit: LengthUnit.cm)
            ..heightChanged('180')
            ..neckChanged('38')
            ..waistChanged('85');
      expect(cubit.state.result, isNull);
      cubit.sexChanged(Sex.male);
      expect(valueOf(cubit.state.result), closeTo(16.11, 0.01));
      cubit.sexChanged(Sex.female);
      expect(cubit.state.result, isNull);
    });
  });

  group('OneRepMaxCubit', () {
    test('the estimate is the same in lb and kg', () {
      final metric =
          OneRepMaxCubit(const EstimateOneRepMax(), weightUnit: WeightUnit.kg)
            ..weightChanged('100')
            ..repsChanged('5');
      final imperial =
          OneRepMaxCubit(const EstimateOneRepMax(), weightUnit: WeightUnit.lb)
            ..weightChanged(lb(100))
            ..repsChanged('5');

      expect(
        valueOf(imperial.state.result).estimateKg,
        closeTo(valueOf(metric.state.result).estimateKg, 1e-9),
      );
    });

    test('the table uses 2.5 kg or 5 lb steps', () {
      bool onSteps(OneRepMax max, double step) => max.loads.every((load) {
        final steps = load.weightKg / step;
        return (steps - steps.round()).abs() < 1e-9;
      });

      final metric =
          OneRepMaxCubit(const EstimateOneRepMax(), weightUnit: WeightUnit.kg)
            ..weightChanged('97')
            ..repsChanged('7');
      final imperial =
          OneRepMaxCubit(const EstimateOneRepMax(), weightUnit: WeightUnit.lb)
            ..weightChanged('213')
            ..repsChanged('7');

      expect(onSteps(valueOf(metric.state.result), 2.5), isTrue);
      expect(
        onSteps(valueOf(imperial.state.result), WeightUnit.lb.toKg(5)),
        isTrue,
      );
    });

    test('reps that are not a whole number are out of range', () {
      final cubit =
          OneRepMaxCubit(const EstimateOneRepMax(), weightUnit: WeightUnit.kg)
            ..weightChanged('100')
            ..repsChanged('5.5');
      expect((cubit.state.result! as OutOfRange).input, CalculatorInput.reps);
      cubit.repsChanged('15');
      expect(
        cubit.state.result,
        const Rejected<OneRepMax>(CalculatorProblem.tooManyReps),
      );
    });
  });

  group('PlatesCubit', () {
    PlatesCubit build(WeightUnit unit, {List<Plate>? plates}) => PlatesCubit(
      const LoadPlates(),
      const CheckBarWeight(),
      const CheckPlate(),
      weightUnit: unit,
      barKg: 20,
      plates: plates ?? UserSettings.defaultPlates(WeightUnit.kg),
    );

    test('a target in lb is converted before loading', () {
      final metric = build(WeightUnit.kg)..targetChanged('100');
      final imperial = build(WeightUnit.lb)..targetChanged(lb(100));
      expect(valueOf(imperial.state.result), valueOf(metric.state.result));
    });

    test('new equipment recalculates the target', () {
      final cubit = build(WeightUnit.kg)..targetChanged('60');
      expect(valueOf(cubit.state.result).totalKg, 60);

      cubit.equipmentChanged(15, const [Plate(weightKg: 10, pairs: 2)]);

      expect(cubit.state.barKg, 15);
      expect(valueOf(cubit.state.result).perSide, const [
        PlateCount(weightKg: 10, count: 2),
      ]);
      expect(valueOf(cubit.state.result).totalKg, 55);
    });

    test('checks for the editor convert from the user unit', () {
      final cubit = build(WeightUnit.lb);
      expect(valueOf(cubit.checkBar('45')), WeightUnit.lb.toKg(45));
      expect(cubit.checkBar(''), isNull);
      expect(cubit.checkBar('500'), isA<OutOfRange<double>>());
      expect(
        valueOf(cubit.checkPlate('2.5', '2')),
        Plate(weightKg: WeightUnit.lb.toKg(2.5), pairs: 2),
      );
      expect(cubit.checkPlate('10', ''), isNull);
      expect(
        (cubit.checkPlate('10', 'x')! as OutOfRange).input,
        CalculatorInput.platePairs,
      );
    });

    test('withPlate replaces a plate of the same weight, largest first', () {
      final cubit = build(
        WeightUnit.kg,
        plates: const [
          Plate(weightKg: 20, pairs: 1),
          Plate(weightKg: 5, pairs: 1),
        ],
      );
      expect(cubit.withPlate(const Plate(weightKg: 10, pairs: 2)), const [
        Plate(weightKg: 20, pairs: 1),
        Plate(weightKg: 10, pairs: 2),
        Plate(weightKg: 5, pairs: 1),
      ]);
      expect(cubit.withPlate(const Plate(weightKg: 5, pairs: 3)), const [
        Plate(weightKg: 20, pairs: 1),
        Plate(weightKg: 5, pairs: 3),
      ]);
      expect(
        cubit.withPlate(
          const Plate(weightKg: 25, pairs: 1),
          replacing: const Plate(weightKg: 20, pairs: 1),
        ),
        const [Plate(weightKg: 25, pairs: 1), Plate(weightKg: 5, pairs: 1)],
      );
      expect(cubit.withoutPlate(const Plate(weightKg: 5, pairs: 1)), const [
        Plate(weightKg: 20, pairs: 1),
      ]);
    });
  });

  group('MacrosCubit', () {
    test('body weight in lb gives the same macros', () {
      final metric = MacrosCubit(const SplitMacros(), weightUnit: WeightUnit.kg)
        ..caloriesChanged('2500')
        ..weightChanged('80');
      final imperial =
          MacrosCubit(const SplitMacros(), weightUnit: WeightUnit.lb)
            ..caloriesChanged('2500')
            ..weightChanged(lb(80));

      final kg = valueOf(metric.state.result);
      final pounds = valueOf(imperial.state.result);
      expect(kg.proteinG, closeTo(144, 1e-9));
      expect(pounds.proteinG, closeTo(kg.proteinG, 1e-9));
      expect(pounds.carbsG, closeTo(kg.carbsG, 1e-9));
    });

    test('protein and fat changes recalculate', () {
      final cubit = MacrosCubit(const SplitMacros(), weightUnit: WeightUnit.kg)
        ..caloriesChanged('2000')
        ..weightChanged('70')
        ..proteinChanged(2.4)
        ..fatChanged(35);
      expect(valueOf(cubit.state.result).carbsG, closeTo(157, 1e-9));
      // 672 kcal of protein + 35 % of 1000 = 1022 kcal > 1000.
      cubit.caloriesChanged('1000');
      expect(
        cubit.state.result,
        const Rejected<Macros>(CalculatorProblem.negativeCarbs),
      );
    });
  });

  group('BodyIndicesCubit', () {
    test('lb/in and kg/cm give the same indices', () {
      final metric =
          BodyIndicesCubit(
              const CalculateBodyIndices(),
              weightUnit: WeightUnit.kg,
              lengthUnit: LengthUnit.cm,
            )
            ..weightChanged('70')
            ..heightChanged('175')
            ..bodyFatChanged('20');
      final imperial =
          BodyIndicesCubit(
              const CalculateBodyIndices(),
              weightUnit: WeightUnit.lb,
              lengthUnit: LengthUnit.inch,
            )
            ..weightChanged(lb(70))
            ..heightChanged(inches(175))
            ..bodyFatChanged('20');

      final kg = valueOf(metric.state.result);
      final pounds = valueOf(imperial.state.result);
      expect(kg.normalizedFfmi, closeTo(18.591, 0.001));
      expect(pounds.bmi, closeTo(kg.bmi, 1e-9));
      expect(pounds.normalizedFfmi, closeTo(kg.normalizedFfmi!, 1e-9));
    });

    test('body fat is optional', () {
      final cubit =
          BodyIndicesCubit(
              const CalculateBodyIndices(),
              weightUnit: WeightUnit.kg,
              lengthUnit: LengthUnit.cm,
            )
            ..weightChanged('80')
            ..heightChanged('180');
      expect(
        valueOf(cubit.state.result),
        isA<BodyIndices>().having((i) => i.ffmi, 'ffmi', isNull),
      );
    });
  });
}
