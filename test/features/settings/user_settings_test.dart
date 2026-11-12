import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

void main() {
  const metric = UserSettings(
    weightUnit: WeightUnit.kg,
    lengthUnit: LengthUnit.cm,
  );
  const imperial = UserSettings(
    weightUnit: WeightUnit.lb,
    lengthUnit: LengthUnit.inch,
  );

  test('US, Liberia and Myanmar default to imperial', () {
    for (final country in ['US', 'LR', 'MM', 'us']) {
      expect(UserSettings.defaultsFor(country), imperial, reason: country);
    }
  });

  test('other or unknown countries default to metric', () {
    for (final country in ['GB', 'DE', 'TR', 'CA', null]) {
      expect(UserSettings.defaultsFor(country), metric, reason: '$country');
    }
  });

  test('the default theme follows the system', () {
    expect(
      UserSettings.defaultsFor('US').themePreference,
      ThemePreference.system,
    );
  });

  group('bar and plates', () {
    double lb(double pounds) => pounds * kgPerLb;

    test('metric: 20 kg bar and 25 to 1.25 kg plates', () {
      expect(metric.barWeightKg, 20);
      expect(metric.plates.map((p) => p.weightKg), [
        25,
        20,
        15,
        10,
        5,
        2.5,
        1.25,
      ]);
    });

    test('imperial: 45 lb bar and 45 to 2.5 lb plates, stored in kg', () {
      expect(imperial.barWeightKg, closeTo(20.411657, 1e-6));
      expect(imperial.plates.map((p) => p.weightKg), [
        lb(45),
        lb(35),
        lb(25),
        lb(10),
        lb(5),
        lb(2.5),
      ]);
    });

    test('every default plate size has pairs', () {
      for (final settings in [metric, imperial]) {
        expect(settings.plates.every((p) => p.pairs > 0), isTrue);
      }
    });

    test('until customised, the equipment follows the weight unit', () {
      final switched = metric.copyWith(weightUnit: WeightUnit.lb);
      expect(switched.barWeightKg, imperial.barWeightKg);
      expect(switched.plates, imperial.plates);
    });

    test('custom equipment stays when the unit changes', () {
      const plates = [Plate(weightKg: 10, pairs: 3)];
      final custom = metric.copyWith(
        customBarWeightKg: 15,
        customPlates: plates,
      );
      final switched = custom.copyWith(weightUnit: WeightUnit.lb);
      expect(switched.barWeightKg, 15);
      expect(switched.plates, plates);
    });

    test('withStandardEquipment drops only the custom equipment', () {
      final custom = imperial.copyWith(
        themePreference: ThemePreference.dark,
        stepGoal: 6000,
        customBarWeightKg: 15,
        customPlates: const [Plate(weightKg: 10, pairs: 3)],
      );
      expect(
        custom.withStandardEquipment(),
        imperial.copyWith(
          themePreference: ThemePreference.dark,
          stepGoal: 6000,
        ),
      );
    });
  });

  test('unit conversions', () {
    expect(WeightUnit.lb.toKg(1), kgPerLb);
    expect(WeightUnit.lb.fromKg(WeightUnit.lb.toKg(225)), closeTo(225, 1e-9));
    expect(WeightUnit.kg.toKg(80), 80);
    expect(LengthUnit.inch.toCm(1), 2.54);
    expect(LengthUnit.inch.fromCm(180), closeTo(70.866, 0.001));
    expect(LengthUnit.cm.fromCm(180), 180);
  });
}
