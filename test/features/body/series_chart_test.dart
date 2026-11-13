import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/core/line_chart.dart';
import 'package:get_workout/features/body/presentation/series_chart.dart';

void main() {
  ChartSeries line(
    List<ChartPoint> points, {
    SeriesAxis axis = SeriesAxis.left,
  }) => ChartSeries(
    points: points,
    color: Colors.blue,
    ticks: const [0, 50, 100],
    axis: axis,
    yLabel: (y) => 'y${y.round()}',
    guide: 50,
  );

  ChartSeries bars(List<ChartPoint> points) => ChartSeries(
    points: points,
    color: Colors.green,
    ticks: const [0, 10],
    axis: SeriesAxis.right,
    yLabel: (y) => 'b${y.round()}',
    bars: true,
  );

  Future<void> pump(
    WidgetTester tester,
    List<ChartSeries> series, {
    double textScale = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SizedBox(
            width: 400,
            child: SeriesChart(
              series: series,
              xMin: 0,
              xMax: 40,
              barSpan: 10,
              xLabel: (x) => 'x${x.round()}',
              selectionLabel: (x) => 'at ${x.round()}',
            ),
          ),
        ),
      ),
    ),
  );

  Rect chart(WidgetTester tester) =>
      tester.getRect(find.byType(CustomPaint).last);

  testWidgets('draws without points', (tester) async {
    await pump(tester, [line(const []), bars(const [])]);
    await tester.tap(find.byType(CustomPaint).last);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('at '), findsNothing);
  });

  testWidgets('a tap picks the point nearest across of any series', (
    tester,
  ) async {
    await pump(tester, [
      line(const [(x: 0, y: 40), (x: 40, y: 60)]),
      // Picked at the middle of its span, x 15.
      bars(const [(x: 10, y: 5)]),
    ]);
    final rect = chart(tester);
    await tester.tapAt(rect.centerRight.translate(-1, 0));
    await tester.pump();
    expect(find.text('at 40'), findsOneWidget);

    await tester.tapAt(Offset(rect.left + rect.width * 0.4, rect.center.dy));
    await tester.pump();
    expect(find.text('at 10'), findsOneWidget);
  });

  testWidgets('new series clear the pick', (tester) async {
    await pump(tester, [
      line(const [(x: 0, y: 1)]),
    ]);
    await tester.tapAt(tester.getCenter(find.byType(CustomPaint).last));
    await tester.pump();
    expect(find.textContaining('at '), findsOneWidget);

    await pump(tester, [
      line(const [(x: 0, y: 2)]),
    ]);
    expect(find.textContaining('at '), findsNothing);
  });

  for (final textScale in [1.0, 2.0, 3.0]) {
    testWidgets('draws both axes at text scale $textScale', (tester) async {
      await pump(tester, [
        line(const [(x: 0, y: 40), (x: 40, y: 60)]),
        line(const [(x: 0, y: 10)], axis: SeriesAxis.none),
        bars(const [(x: 0, y: 5), (x: 30, y: 10)]),
      ], textScale: textScale);
      expect(tester.takeException(), isNull);
    });
  }
}
