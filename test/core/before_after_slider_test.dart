import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/core/before_after_slider.dart';

void main() {
  test('the split is the share of the width left of the touch, kept '
      'inside', () {
    expect(splitAt(100, 400), 0.25);
    expect(splitAt(400, 400), 1);
    expect(splitAt(-20, 400), 0);
    expect(splitAt(500, 400), 1);
    expect(splitAt(10, 0), 0.5);
  });

  group('BeforeAfterSlider', () {
    const width = 400.0;

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 300,
              child: BeforeAfterSlider(
                before: ColoredBox(color: Colors.black, child: Text('before')),
                after: ColoredBox(color: Colors.white, child: Text('after')),
              ),
            ),
          ),
        ),
      ),
    );

    Rect slider(WidgetTester tester) =>
        tester.getRect(find.byType(BeforeAfterSlider));

    /// Where the bar is, from the slider's left edge.
    double bar(WidgetTester tester) =>
        tester.getCenter(find.byKey(BeforeAfterSlider.barKey)).dx -
        slider(tester).left;

    /// The picture holding [text].
    Finder picture(String text) => find
        .ancestor(of: find.text(text), matching: find.byType(ColoredBox))
        .first;

    testWidgets('starts in the middle with both pictures the slider\'s '
        'size', (tester) async {
      await pump(tester);

      expect(bar(tester), width / 2);
      expect(
        tester.getRect(picture('before')),
        tester.getRect(picture('after')),
      );
      expect(tester.getSize(picture('after')), slider(tester).size);
    });

    testWidgets('dragging moves the bar with the finger', (tester) async {
      await pump(tester);
      final start = slider(tester).center;

      await tester.dragFrom(start, const Offset(-100, 0));
      await tester.pump();
      expect(bar(tester), closeTo(100, 1));

      await tester.dragFrom(slider(tester).center, const Offset(50, 0));
      await tester.pump();
      expect(bar(tester), closeTo(width / 2 + 50, 1));
    });

    testWidgets('the bar stops at the edges', (tester) async {
      await pump(tester);
      final center = slider(tester).center;

      await tester.dragFrom(center, const Offset(-600, 0));
      await tester.pump();
      expect(bar(tester), 0);

      await tester.dragFrom(center, const Offset(600, 0));
      await tester.pump();
      expect(bar(tester), width);
    });

    testWidgets('a tap moves the bar there', (tester) async {
      await pump(tester);

      await tester.tapAt(slider(tester).centerLeft + const Offset(300, 0));
      await tester.pump();
      expect(bar(tester), 300);
    });
  });
}
