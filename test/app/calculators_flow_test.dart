import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/calculators/presentation/calories_page.dart';

import 'flow_harness.dart';

void main() {
  late FlowApp app;

  setUpAll(registerFlowFallbacks);
  setUp(() => app = FlowApp());
  tearDown(() => app.dispose());

  Future<void> tapText(WidgetTester tester, String text) =>
      app.tapText(tester, text);

  /// The number sheet's field, which shows the unit inside its box.
  final field = find.byType(ForgeTextField);

  /// Types [value] into the row [title]'s number sheet and saves it.
  Future<void> enter(WidgetTester tester, String title, String value) async {
    await tapText(tester, title);
    await tester.enterText(
      find.descendant(of: field, matching: find.byType(EditableText)),
      value,
    );
    await tapText(tester, 'Save');
  }

  testWidgets('Calories fills in row by row; the result replaces the missing '
      'card, which a cleared input brings back', (tester) async {
    await app.startAs(tester, guest);
    await app.tapTab(tester, 'Profile');
    await tapText(tester, 'Calculators');
    await tapText(tester, 'Calories');
    expect(find.byType(CaloriesPage), findsOneWidget);
    expect(
      find.text(
        'Add your sex, age, height, weight and activity to see the result.',
      ),
      findsOneWidget,
    );

    // The sheet is titled by the row and has the unit inside the box.
    await tapText(tester, 'Weight');
    expect(find.text('Weight'), findsNWidgets(3));
    expect(
      find.descendant(of: field, matching: find.text('kg')),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(of: field, matching: find.byType(EditableText)),
      '80',
    );
    await tapText(tester, 'Save');
    expect(field, findsNothing);
    expect(find.text('80 kg'), findsOneWidget);
    expect(
      find.text('Add your sex, age, height and activity to see the result.'),
      findsOneWidget,
    );

    await tapText(tester, 'Sex');
    await tapText(tester, 'Female');
    await enter(tester, 'Age', '30');
    await tapText(tester, 'Height');
    expect(
      find.descendant(of: field, matching: find.text('cm')),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(of: field, matching: find.byType(EditableText)),
      '170',
    );
    await tapText(tester, 'Save');
    await tapText(tester, 'Activity');
    await tapText(tester, 'Moderate · 3–5 days');

    expect(find.text('170 cm'), findsOneWidget);
    expect(find.textContaining('to see the result'), findsNothing);
    expect(find.text('Daily energy need'), findsOneWidget);
    expect(find.text('Keep weight'), findsOneWidget);
    final estimate = find.textContaining('kcal');
    expect(estimate, findsWidgets);
    final before = tester.widget<Text>(estimate.first).data;

    // A new weight updates the result.
    await enter(tester, 'Weight', '90');
    expect(find.text('90 kg'), findsOneWidget);
    expect(tester.widget<Text>(estimate.first).data, isNot(before));

    // Cleared, the age is missing again.
    await tapText(tester, 'Age');
    await tapText(tester, 'Clear');
    expect(find.text('Add your age to see the result.'), findsOneWidget);
    expect(find.text('Keep weight'), findsNothing);
  });
}
