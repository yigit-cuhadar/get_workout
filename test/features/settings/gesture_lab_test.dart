import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/settings/presentation/gesture_lab/gesture_lab_page.dart';
import 'package:get_workout/features/settings/presentation/gesture_lab/scroll_lab_page.dart';

Future<void> _pump(WidgetTester tester, Widget page) => tester.pumpWidget(
  MaterialApp(
    theme: AppPreset.slate.lightTheme().copyWith(platform: TargetPlatform.iOS),
    home: page,
  ),
);

Future<void> _open(WidgetTester tester, BackOption option) async {
  await tester.scrollUntilVisible(find.text(option.title), 100);
  await tester.tap(find.text(option.title));
  await tester.pumpAndSettle();
}

/// A right swipe starting in the middle of the page.
Future<void> _swipeFromMiddle(WidgetTester tester) async {
  await tester.dragFrom(const Offset(400, 300), const Offset(500, 0));
  await tester.pumpAndSettle();
}

void main() {
  test('the lab has no entry in a release build', () {
    expect(gestureLabEntry(release: true), isNull);
    expect(gestureLabEntry(release: false), isNotNull);
  });

  for (final option in BackOption.values) {
    testWidgets('${option.title} opens its page and back leaves it', (
      tester,
    ) async {
      await _pump(tester, const GestureLabPage());
      await _open(tester, option);
      expect(find.byType(LabTestPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      if (option.guarded) {
        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(LabTestPage), findsNothing);
    });
  }

  testWidgets('the default page ignores a swipe from the middle', (
    tester,
  ) async {
    await _pump(tester, const GestureLabPage());
    await _open(tester, BackOption.flutterDefault);
    await _swipeFromMiddle(tester);
    expect(find.byType(LabTestPage), findsOneWidget);
  });

  testWidgets('the full-width page leaves on a swipe from the middle', (
    tester,
  ) async {
    await _pump(tester, const GestureLabPage());
    await _open(tester, BackOption.fullWidth);
    await _swipeFromMiddle(tester);
    expect(find.byType(LabTestPage), findsNothing);
  });

  testWidgets('a guarded full-width page asks after the swipe and stays', (
    tester,
  ) async {
    await _pump(tester, const GestureLabPage());
    await _open(tester, BackOption.fullWidthConfirm);
    await _swipeFromMiddle(tester);
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(LabTestPage), findsOneWidget);
  });

  testWidgets('the scroll lab switches physics and the scrollbar', (
    tester,
  ) async {
    await _pump(tester, const ScrollLabPage());
    ScrollPhysics? physics() =>
        tester.widget<ListView>(find.byType(ListView)).physics;
    expect(physics(), isNull);

    await tester.tap(find.text(ScrollOption.clamping.label));
    await tester.pump();
    expect(physics(), isA<ClampingScrollPhysics>());
    expect(find.text('Active: ${ScrollOption.clamping.label}'), findsOneWidget);

    expect(find.byType(Scrollbar), findsNothing);
    await tester.tap(find.byType(ForgeSwitch));
    await tester.pump();
    expect(find.byType(Scrollbar), findsOneWidget);
  });
}
