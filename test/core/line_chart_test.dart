import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/core/line_chart.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<ChartPoint> points) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: LineChart(
                points: points,
                xLabel: (x) => 'x${x.round()}',
                yLabel: (y) => 'y${y.round()}',
                pointLabel: (index) => 'point $index',
              ),
            ),
          ),
        ),
      );

  testWidgets('draws without points', (tester) async {
    await pump(tester, const []);
    await tester.tap(find.byType(CustomPaint).last);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('point'), findsNothing);
  });

  testWidgets('one point is picked by a tap anywhere', (tester) async {
    await pump(tester, const [(x: 5, y: 100)]);
    await tester.tapAt(tester.getTopLeft(find.byType(CustomPaint).last));
    await tester.pump();
    expect(find.text('point 0'), findsOneWidget);
  });

  testWidgets('a tap picks the point nearest across', (tester) async {
    await pump(tester, const [(x: 0, y: 100), (x: 10, y: 110), (x: 20, y: 90)]);
    final chart = tester.getRect(find.byType(CustomPaint).last);
    await tester.tapAt(chart.centerRight.translate(-1, 0));
    await tester.pump();
    expect(find.text('point 2'), findsOneWidget);
  });

  testWidgets('new points clear the pick', (tester) async {
    await pump(tester, const [(x: 0, y: 1), (x: 1, y: 2)]);
    await tester.tapAt(tester.getCenter(find.byType(CustomPaint).last));
    await tester.pump();
    expect(find.textContaining('point'), findsOneWidget);

    await pump(tester, const [(x: 0, y: 1), (x: 1, y: 3)]);
    expect(find.textContaining('point'), findsNothing);
  });
}
