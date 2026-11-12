import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/core/chart_geometry.dart';

void main() {
  group('niceTicks', () {
    test('round steps covering the values', () {
      expect(niceTicks(83, 117), [80, 90, 100, 110, 120]);
    });

    test('steps of 1, 2 or 5 times a power of ten', () {
      expect(niceTicks(0, 1), [0, 0.5, 1]);
      expect(niceTicks(0, 7), [0, 2, 4, 6, 8]);
      expect(niceTicks(102.5, 140), [100, 110, 120, 130, 140]);
      expect(niceTicks(0, 3000), [0, 1000, 2000, 3000]);
    });

    test('decimal steps without floating point noise', () {
      expect(niceTicks(0.1, 0.7), [0.0, 0.2, 0.4, 0.6, 0.8]);
    });

    test('a single value gets an axis around it', () {
      final ticks = niceTicks(100, 100);
      expect(ticks.first, lessThan(100));
      expect(ticks.last, greaterThan(100));
      expect(niceTicks(0, 0), [-1, -0.5, 0, 0.5, 1]);
    });

    test('ends in either order', () {
      expect(niceTicks(117, 83), niceTicks(83, 117));
    });

    test('nothing for values that are not finite', () {
      expect(niceTicks(double.nan, 1), isEmpty);
      expect(niceTicks(0, double.infinity), isEmpty);
    });
  });

  group('scale', () {
    double map(double value) => scale(
      value,
      domainMin: 100,
      domainMax: 200,
      rangeMin: 300,
      rangeMax: 0,
    );

    test('maps the domain onto the range, also reversed', () {
      expect(map(100), 300);
      expect(map(200), 0);
      expect(map(150), 150);
    });

    test('a domain of no width maps to the middle', () {
      expect(
        scale(5, domainMin: 5, domainMax: 5, rangeMin: 0, rangeMax: 40),
        20,
      );
    });
  });

  group('spreadTicks', () {
    test('evenly spaced, ends included', () {
      expect(spreadTicks(0, 90, 4), [0, 30, 60, 90]);
    });

    test('one value when the ends meet or one is asked for', () {
      expect(spreadTicks(5, 5, 4), [5]);
      expect(spreadTicks(0, 90, 1), [0]);
    });
  });

  group('labelsThatFit', () {
    test('as many labels as fit with their gaps', () {
      expect(labelsThatFit(300, 50, gap: 10), 5);
      expect(labelsThatFit(290, 50, gap: 10), 5);
      expect(labelsThatFit(289, 50, gap: 10), 4);
    });

    test('at least one', () {
      expect(labelsThatFit(10, 50, gap: 10), 1);
      expect(labelsThatFit(100, 0, gap: 10), 1);
    });
  });

  group('nearestIndex', () {
    test('the value nearest across, the first of a tie', () {
      expect(nearestIndex([0, 10, 20], 14), 1);
      expect(nearestIndex([0, 10, 20], 15), 1);
      expect(nearestIndex([0, 10, 20], 99), 2);
      expect(nearestIndex([0, 10, 20], -5), 0);
    });

    test('none without values', () {
      expect(nearestIndex([], 3), isNull);
    });
  });
}
