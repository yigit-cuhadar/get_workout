import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/core/chart_geometry.dart';

void main() {
  group('niceTicks', () {
    test('round steps covering the values', () {
      expect(niceTicks(83, 117, precision: 1), [80, 90, 100, 110, 120]);
    });

    test('steps of 1, 2 or 5 times a power of ten', () {
      expect(niceTicks(0, 1, precision: 0.1), [0, 0.5, 1]);
      expect(niceTicks(0, 7, precision: 1), [0, 2, 4, 6, 8]);
      expect(niceTicks(102.5, 140, precision: 1), [100, 110, 120, 130, 140]);
      expect(niceTicks(0, 3000, precision: 1), [0, 1000, 2000, 3000]);
    });

    test('decimal steps without floating point noise', () {
      expect(niceTicks(0.1, 0.7, precision: 0.1), [0.0, 0.2, 0.4, 0.6, 0.8]);
    });

    test('labels at the precision never repeat', () {
      for (final (min, max, precision, decimals) in [
        (87.83, 88.0, 0.1, 1),
        (250.0, 250.04, 1.0, 0),
        (99.99, 100.01, 1.0, 0),
      ]) {
        final ticks = niceTicks(min, max, precision: precision);
        final labels = [
          for (final tick in ticks) tick.toStringAsFixed(decimals),
        ];
        expect(labels.toSet(), hasLength(labels.length), reason: '$labels');
        expect(ticks.first, lessThanOrEqualTo(min));
        expect(ticks.last, greaterThanOrEqualTo(max));
      }
    });

    test('a tiny change does not fill the height', () {
      // 0.17 apart, labelled in whole numbers: at least four steps of one.
      final ticks = niceTicks(87.83, 88.0, precision: 1);
      expect(ticks.last - ticks.first, greaterThanOrEqualTo(4));
      expect((88.0 - 87.83) / (ticks.last - ticks.first), lessThan(0.05));
      expect(niceTicks(250, 250.04, precision: 1), [
        248,
        249,
        250,
        251,
        252,
        253,
      ]);
    });

    test('a single value gets an axis around it', () {
      final ticks = niceTicks(100, 100, precision: 1);
      expect(ticks.first, lessThan(100));
      expect(ticks.last, greaterThan(100));
    });

    test('values at or above zero keep the axis there', () {
      expect(niceTicks(0, 0, precision: 0.5), [0, 0.5, 1, 1.5, 2]);
      expect(niceTicks(0.5, 0.6, precision: 1).first, 0);
    });

    test('ends in either order', () {
      expect(
        niceTicks(117, 83, precision: 1),
        niceTicks(83, 117, precision: 1),
      );
    });

    test('nothing for values that are not finite', () {
      expect(niceTicks(double.nan, 1, precision: 1), isEmpty);
      expect(niceTicks(0, double.infinity, precision: 1), isEmpty);
    });
  });

  group('thinTicks', () {
    final ticks = <double>[0, 1, 2, 3, 4, 5, 6];

    test('all when they fit', () {
      expect(thinTicks(ticks, 7), ticks);
    });

    test('every k-th from the first, at most as many as fit', () {
      expect(thinTicks(ticks, 4), [0, 2, 4, 6]);
      expect(thinTicks(ticks, 3), [0, 3, 6]);
      expect(thinTicks(ticks, 2), [0, 6]);
      expect(thinTicks(<double>[0, 1, 2, 3, 4], 3), [0, 2, 4]);
      expect(thinTicks(<double>[0, 1, 2, 3, 4, 5], 3), [0, 3]);
    });

    test('the first alone when fewer than two fit', () {
      expect(thinTicks(ticks, 1), [0]);
      expect(thinTicks(ticks, 0), [0]);
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
    test('centred labels spaced at least the gap apart', () {
      // Five labels 50 wide are 60 apart over 240.
      expect(labelsThatFit(240, 50, gap: 10), 5);
      expect(labelsThatFit(239, 50, gap: 10), 4);
    });

    test('at least one', () {
      expect(labelsThatFit(10, 50, gap: 10), 1);
      expect(labelsThatFit(100, 0, gap: 10), 1);
    });
  });

  group('chartFrame', () {
    const size = Size(360, 225);
    const gap = 8.0;

    for (final textScale in [1.0, 2.0, 3.0]) {
      group('at text scale $textScale', () {
        final labelHeight = 14 * textScale;
        final yWidth = 24 * textScale;
        final xWidth = 40 * textScale;
        final frame = chartFrame(
          size,
          yLabelWidth: yWidth,
          xLabelWidth: xWidth,
          labelHeight: labelHeight,
          gap: gap,
        );
        final plot = frame.plot;

        test('everything stays inside the chart', () {
          expect(plot.left, greaterThanOrEqualTo(yWidth + gap));
          expect(plot.top, greaterThanOrEqualTo(labelHeight / 2));
          expect(plot.right + xWidth / 2, lessThanOrEqualTo(size.width));
          expect(
            xLabelsTop(plot, labelHeight, gap) + labelHeight,
            lessThanOrEqualTo(size.height),
          );
          expect(plot.width, greaterThanOrEqualTo(0));
          expect(plot.height, greaterThanOrEqualTo(0));
        });

        test('the lowest value label ends above the labels below', () {
          final lowestBottom = plot.bottom + labelHeight / 2;
          expect(
            xLabelsTop(plot, labelHeight, gap) - lowestBottom,
            greaterThanOrEqualTo(gap),
          );
        });

        test('the value labels that fit do not overlap', () {
          final ticks = thinTicks(
            niceTicks(60, 140, precision: 1, count: 8),
            frame.yLabels,
          );
          final spacing = ticks.length < 2
              ? double.infinity
              : (ticks[1] - ticks[0]) / (140 - 60) * plot.height;
          expect(spacing, greaterThanOrEqualTo(labelHeight + gap - 1e-9));
        });

        test('the labels below that fit do not overlap', () {
          final count = frame.xLabels;
          final spacing = count < 2
              ? double.infinity
              : plot.width / (count - 1);
          expect(spacing, greaterThanOrEqualTo(xWidth + gap));
        });
      });
    }

    test('fewer labels fit as the text grows', () {
      ChartFrame at(double scale) => chartFrame(
        size,
        yLabelWidth: 24 * scale,
        xLabelWidth: 40 * scale,
        labelHeight: 14 * scale,
        gap: gap,
      );
      expect(at(1).yLabels, greaterThan(at(3).yLabels));
      expect(at(1).xLabels, greaterThan(at(3).xLabels));
    });

    test('labels wider than the chart leave an empty plot, not a negative '
        'one', () {
      final frame = chartFrame(
        const Size(100, 40),
        yLabelWidth: 90,
        xLabelWidth: 80,
        labelHeight: 30,
        gap: gap,
      );
      expect(frame.plot.width, 0);
      expect(frame.plot.height, 0);
      expect(frame.yLabels, 1);
      expect(frame.xLabels, 1);
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
