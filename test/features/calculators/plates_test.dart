import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';
import 'package:get_workout/features/calculators/domain/plates.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

void main() {
  final kgPlates = UserSettings.defaultPlates(WeightUnit.kg);
  final lbPlates = UserSettings.defaultPlates(WeightUnit.lb);
  final lbBar = UserSettings.defaultBarWeightKg(WeightUnit.lb);

  PlateLoad load(double targetKg, {double barKg = 20, List<Plate>? plates}) =>
      (loadPlates(
        targetKg: targetKg,
        barKg: barKg,
        plates: plates ?? kgPlates,
      ) as Calculated<PlateLoad>).value;

  List<(double, int)> perSide(PlateLoad load) => [
    for (final plate in load.perSide) (plate.weightKg, plate.count),
  ];

  test('largest plates first', () {
    // 100 kg on a 20 kg bar: 40 per side = 25 + 15 (not 20 + 15 + 5).
    final result = load(100);
    expect(perSide(result), [(25.0, 1), (15.0, 1)]);
    expect(result.totalKg, 100);
    expect(result.exact, isTrue);
  });

  test('uses several of a plate', () {
    // 140 kg: 60 per side = 2 × 25 + 10.
    expect(perSide(load(140)), [(25.0, 2), (10.0, 1)]);
  });

  test('the bar alone', () {
    final result = load(20);
    expect(result.perSide, isEmpty);
    expect(result.totalKg, 20);
    expect(result.exact, isTrue);
  });

  test('an unreachable target gives the closest weight below', () {
    // 21 kg needs 0.5 per side; the smallest plate is 1.25.
    final result = load(21);
    expect(result.perSide, isEmpty);
    expect(result.totalKg, 20);
    expect(result.exact, isFalse);

    // 103 kg: 41.5 per side; 25 + 15 + 1.25 = 41.25 → 102.5 kg.
    final below = load(103);
    expect(below.totalKg, 102.5);
    expect(below.exact, isFalse);
  });

  test('beyond the inventory, everything is loaded', () {
    // Per side at most 4·25 + 20 + 15 + 10 + 5 + 2.5 + 1.25 = 153.75.
    final result = load(500);
    expect(result.totalKg, 20 + 2 * 153.75);
    expect(result.exact, isFalse);
  });

  test('finds exact loads that taking the largest plate first misses', () {
    // 30 per side from 25 × 1 and 15 × 2: greedy stops at 25.
    final result = load(
      80,
      plates: const [
        Plate(weightKg: 25, pairs: 1),
        Plate(weightKg: 15, pairs: 2),
      ],
    );
    expect(perSide(result), [(15.0, 2)]);
    expect(result.exact, isTrue);
  });

  test('plate order in the inventory does not matter', () {
    expect(load(100, plates: kgPlates.reversed.toList()), load(100));
  });

  test('sizes without pairs are not used', () {
    final result = load(
      70,
      plates: const [
        Plate(weightKg: 25, pairs: 0),
        Plate(weightKg: 20, pairs: 1),
        Plate(weightKg: 5, pairs: 1),
      ],
    );
    expect(perSide(result), [(20.0, 1), (5.0, 1)]);
  });

  test('no plates at all gives the bar', () {
    final result = load(60, plates: const []);
    expect(result.totalKg, 20);
    expect(result.exact, isFalse);
  });

  group('pounds', () {
    double lb(double kg) => WeightUnit.lb.fromKg(kg);

    PlateLoad loadLb(double targetLb) =>
        load(WeightUnit.lb.toKg(targetLb), barKg: lbBar, plates: lbPlates);

    test('225 lb is two 45s a side', () {
      final result = loadLb(225);
      expect(result.perSide, [
        PlateCount(weightKg: WeightUnit.lb.toKg(45), count: 2),
      ]);
      expect(lb(result.totalKg), closeTo(225, 1e-9));
      expect(result.exact, isTrue);
    });

    test('230 lb adds a 2.5 a side', () {
      final result = loadLb(230);
      expect(result.perSide, [
        PlateCount(weightKg: WeightUnit.lb.toKg(45), count: 2),
        PlateCount(weightKg: WeightUnit.lb.toKg(2.5), count: 1),
      ]);
      expect(lb(result.totalKg), closeTo(230, 1e-9));
    });

    test('an odd target rounds down to what can be loaded', () {
      // 137 lb: 46 per side; 45 + nothing (smallest 2.5) → 135 lb.
      final result = loadLb(137);
      expect(lb(result.totalKg), closeTo(135, 1e-9));
      expect(result.exact, isFalse);
    });
  });

  test('a target below the bar is rejected', () {
    expect(
      loadPlates(targetKg: 15, barKg: 20, plates: kgPlates),
      const Rejected<PlateLoad>(CalculatorProblem.targetBelowBar),
    );
  });

  test('out-of-range target or bar', () {
    expect(
      loadPlates(targetKg: 0, barKg: 20, plates: kgPlates),
      const OutOfRange<PlateLoad>(
        CalculatorInput.targetWeight,
        targetWeightRangeKg,
      ),
    );
    expect(
      loadPlates(targetKg: 100, barKg: -1, plates: kgPlates),
      const OutOfRange<PlateLoad>(CalculatorInput.barWeight, barWeightRangeKg),
    );
  });

  test('checkBarWeight', () {
    expect(checkBarWeight(15), const Calculated(15.0));
    expect(checkBarWeight(0), const Calculated(0.0));
    expect(checkBarWeight(101), isA<OutOfRange<double>>());
  });

  test('checkPlate', () {
    expect(
      checkPlate(weightKg: 0.5, pairs: 3),
      const Calculated(Plate(weightKg: 0.5, pairs: 3)),
    );
    expect(
      checkPlate(weightKg: 0.1, pairs: 1),
      const OutOfRange<Plate>(CalculatorInput.plateWeight, plateWeightRangeKg),
    );
    expect(
      checkPlate(weightKg: 10, pairs: 21),
      const OutOfRange<Plate>(CalculatorInput.platePairs, platePairsRange),
    );
    expect(checkPlate(weightKg: 10, pairs: -1), isA<OutOfRange<Plate>>());
  });
}
