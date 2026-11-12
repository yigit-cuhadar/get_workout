import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/core/bar_chart.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<double> values, {
    double? target,
    double textScale = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SizedBox(
            width: 320,
            child: BarChart(
              values: values,
              xLabel: (index) => 'Nov $index',
              yLabel: (y) => y.toStringAsFixed(0),
              yPrecision: 1,
              barLabel: (index) => 'bar $index',
              semanticLabel: 'chart of ${values.length}',
              target: target,
            ),
          ),
        ),
      ),
    ),
  );

  Rect chart(WidgetTester tester) =>
      tester.getRect(find.byType(CustomPaint).last);

  testWidgets('draws without values', (tester) async {
    await pump(tester, const []);
    await tester.tap(find.byType(CustomPaint).last);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('bar'), findsNothing);
  });

  testWidgets('a tap picks the bar nearest across', (tester) async {
    await pump(tester, const [100, 200, 300]);
    await tester.tapAt(chart(tester).centerRight.translate(-1, 0));
    await tester.pump();
    expect(find.text('bar 2'), findsOneWidget);
  });

  testWidgets('new values clear the pick', (tester) async {
    await pump(tester, const [1, 2]);
    await tester.tapAt(chart(tester).center);
    await tester.pump();
    expect(find.textContaining('bar'), findsOneWidget);

    await pump(tester, const [1, 3]);
    expect(find.textContaining('bar'), findsNothing);
  });

  for (final textScale in [1.0, 2.0, 3.0]) {
    testWidgets('draws 30 bars and a target at text scale $textScale', (
      tester,
    ) async {
      await pump(
        tester,
        [for (var i = 0; i < 30; i++) i * 400.0],
        target: 10000,
        textScale: textScale,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('all zero draws', (tester) async {
    await pump(tester, List.filled(7, 0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen readers get the summary', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const [1, 2, 3]);
    expect(find.bySemanticsLabel('chart of 3'), findsOneWidget);
    handle.dispose();
  });
}
