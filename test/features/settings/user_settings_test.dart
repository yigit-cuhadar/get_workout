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

  group('week start', () {
    test('is automatic by default', () {
      expect(UserSettings.defaultsFor('US').weekStart, WeekStart.automatic);
    });

    test('automatic follows the locale, a chosen day overrides it', () {
      for (final locale in [DateTime.monday, DateTime.sunday, 6]) {
        expect(WeekStart.automatic.firstWeekday(locale), locale);
        expect(WeekStart.monday.firstWeekday(locale), DateTime.monday);
        expect(WeekStart.sunday.firstWeekday(locale), DateTime.sunday);
        expect(WeekStart.saturday.firstWeekday(locale), DateTime.saturday);
      }
    });
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
        weekStart: WeekStart.monday,
        stepGoal: 6000,
        customBarWeightKg: 15,
        customPlates: const [Plate(weightKg: 10, pairs: 3)],
      );
      expect(
        custom.withStandardEquipment(),
        imperial.copyWith(
          themePreference: ThemePreference.dark,
          weekStart: WeekStart.monday,
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

  group('shown lifted weights', () {
    const lb = WeightUnit.lb;
    const kg = WeightUnit.kg;

    test('typed in kg, shown in lb: whole lb', () {
      expect(lb.shownFromKg(80), 176);
      expect(lb.shownFromKg(100), 220);
      expect(lb.shownFromKg(22.5), 50);
      expect(lb.shownFromKg(1.25), 3);
    });

    test('typed in lb, shown in kg: nearest half kg', () {
      expect(kg.shownFromKg(lb.toKg(45)), 20.5);
      expect(kg.shownFromKg(lb.toKg(135)), 61);
      expect(kg.shownFromKg(lb.toKg(2.5)), 1);
      // 1.36 kg is nearer 1.5 than 1.
      expect(kg.shownFromKg(lb.toKg(3)), 1.5);
    });

    test('typed in the shown unit: as it is', () {
      expect(lb.shownFromKg(lb.toKg(12.5)), 12.5);
      expect(lb.shownFromKg(lb.toKg(176.37)), 176.37);
      expect(lb.shownFromKg(lb.toKg(0.25)), 0.25);
      expect(kg.shownFromKg(22.75), 22.75);
      expect(kg.shownFromKg(20.41), 20.41);
      expect(kg.shownFromKg(0), 0);
      expect(lb.shownFromKg(0), 0);
    });

    // Every two-decimal weight in the valid range (1000 kg, 2205 lb) comes
    // back as typed in its own unit and shows rounded in the other.
    test('every two-decimal kg weight up to 1000 kg', () {
      for (var hundredths = 0; hundredths <= 100000; hundredths++) {
        final typed = hundredths / 100;
        expect(kg.shownFromKg(typed), typed);
        final inLb = lb.shownFromKg(typed);
        if (typed >= 0.5) expect(inLb, inLb.roundToDouble(), reason: '$typed');
      }
    });

    test('every two-decimal lb weight up to 2205 lb', () {
      for (var hundredths = 0; hundredths <= 220500; hundredths++) {
        final typed = hundredths / 100;
        final stored = lb.toKg(typed);
        expect(lb.shownFromKg(stored), typed);
        final inKg = kg.shownFromKg(stored);
        if (typed >= 0.6) {
          expect(inKg * 2, (inKg * 2).roundToDouble(), reason: '$typed');
        }
      }
    });

    test('the closest calls to the other grid', () {
      expect(lb.shownFromKg(lb.toKg(538.92)), 538.92);
      expect(kg.shownFromKg(lb.toKg(538.92)), 244.5);
      expect(kg.shownFromKg(244.45), 244.45);
      expect(lb.shownFromKg(244.45), 539);
    });

    test('a positive weight never shows as 0', () {
      expect(lb.shownFromKg(0.2), 0.44);
      expect(kg.shownFromKg(lb.toKg(0.5)), 0.23);
      expect(lb.shownFromKg(0.001), 0.01);
      expect(lb.estimatedFromKg(0.1), 0.22);
      expect(kg.estimatedFromKg(0.2), 0.2);
    });

    test('an estimated one-rep max is always rounded', () {
      expect(lb.estimatedFromKg(lb.toKg(225.4)), 225);
      expect(lb.estimatedFromKg(100), 220);
      expect(kg.estimatedFromKg(102.3), 102.5);
      expect(kg.estimatedFromKg(102.2), 102);
      expect(kg.estimatedFromKg(lb.toKg(225)), 102);
    });

    test('a shown weight shows the same again', () {
      for (final value in [176.0, 176.37, 176.3698, 20.4117, 20.5, 0.004]) {
        for (final unit in WeightUnit.values) {
          expect(unit.shown(unit.shown(value)), unit.shown(value));
        }
      }
    });
  });

  group('warm-up settings', () {
    test('each scheme has its sets; off has none but ramps as standard', () {
      List<WarmupStep> steps(WarmupScheme scheme) =>
          WarmupSettings(scheme: scheme).steps;
      expect(steps(WarmupScheme.off), isEmpty);
      expect(steps(WarmupScheme.light), [const WarmupStep(60, 6)]);
      expect(steps(WarmupScheme.standard), [
        const WarmupStep(50, 8),
        const WarmupStep(75, 4),
      ]);
      expect(steps(WarmupScheme.full), [
        const WarmupStep(40, 8),
        const WarmupStep(60, 5),
        const WarmupStep(80, 2),
      ]);
      expect(
        const WarmupSettings(scheme: WarmupScheme.off).rampSteps,
        steps(WarmupScheme.standard),
      );
    });

    test('custom starts from the scheme chosen, then keeps its own', () {
      const full = WarmupSettings(scheme: WarmupScheme.full);
      expect(full.toCustom().steps, WarmupScheme.full.presetSteps);
      const own = WarmupSettings(custom: [WarmupStep(30, 10)]);
      expect(own.toCustom().steps, [const WarmupStep(30, 10)]);
      expect(
        const WarmupSettings(scheme: WarmupScheme.off).toCustom().steps,
        WarmupScheme.standard.presetSteps,
      );
    });

    test('a set is checked against the limits', () {
      expect(validateWarmupStep(const WarmupStep(10, 1)), isEmpty);
      expect(validateWarmupStep(const WarmupStep(95, 20)), isEmpty);
      expect(validateWarmupStep(const WarmupStep(9, 21)), {
        WarmupStepIssue.percentOutOfRange,
        WarmupStepIssue.repsOutOfRange,
      });
      expect(validateWarmupStep(const WarmupStep(96, 0)), {
        WarmupStepIssue.percentOutOfRange,
        WarmupStepIssue.repsOutOfRange,
      });
    });

    test('an added set goes midway to 90 % with half the reps', () {
      expect(nextWarmupStep(const []), const WarmupStep(50, 8));
      expect(
        nextWarmupStep(const [WarmupStep(50, 8), WarmupStep(75, 4)]),
        const WarmupStep(85, 2),
      );
      expect(
        nextWarmupStep(const [WarmupStep(95, 1)]),
        const WarmupStep(95, 1),
      );
    });
  });

  group('StepGoal', () {
    test('minus and plus move by 100 within the limits', () {
      expect(StepGoal.stepped(8000, 1), 8100);
      expect(StepGoal.stepped(8000, -1), 7900);
      expect(StepGoal.stepped(StepGoal.min, -1), StepGoal.min);
      expect(StepGoal.stepped(StepGoal.max, 1), StepGoal.max);
    });

    test('a typed goal lands on the nearest 100', () {
      expect(StepGoal.typed(8000), 8000);
      expect(StepGoal.typed(8049), 8000);
      expect(StepGoal.typed(8050), 8100);
      expect(StepGoal.typed(StepGoal.min), StepGoal.min);
      expect(StepGoal.typed(StepGoal.max), StepGoal.max);
    });

    test('a typed goal outside the limits is refused', () {
      expect(StepGoal.typed(999), isNull);
      expect(StepGoal.typed(50001), isNull);
      expect(StepGoal.typed(0), isNull);
    });
  });
}
