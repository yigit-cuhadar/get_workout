import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/today/presentation/widgets/rest_day_card.dart';

import '../../../component_harness.dart';

void main() {
  final taps = <String>[];

  RestDayCard card({required int? steps, bool locked = false}) => RestDayCard(
    next: 'Pull, Mon, Nov 16',
    nextDay: 'Pull',
    steps: steps,
    goal: 10000,
    onSteps: () => taps.add('steps'),
    onLogCardio: () => taps.add('cardio'),
    onStartEarly: () => taps.add('early'),
    locked: locked,
  );

  setUp(taps.clear);

  testWidgets('offers a walk toward the goal, cardio and the next day early, '
      'but no empty workout', (tester) async {
    await pumpComponent(tester, card(steps: 6240));

    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('Next: Pull, Mon, Nov 16'), findsOneWidget);
    expect(find.text('3,760 steps to your goal'), findsOneWidget);

    await tester.tap(find.text('Go for a walk'));
    await tester.tap(find.text('Log cardio'));
    await tester.tap(find.text('Start Pull early'));
    expect(find.text('Start empty workout'), findsNothing);
    expect(taps, ['steps', 'cardio', 'early']);
  });

  testWidgets('a locked next day keeps its button, which opens the paywall', (
    tester,
  ) async {
    await pumpComponent(tester, card(steps: 6240, locked: true));

    expect(
      find.descendant(
        of: find.widgetWithText(ForgeButton, 'Start Pull early'),
        matching: find.byWidgetPredicate(
          (widget) => widget is ForgeIcon && widget.icon == ForgeIcons.lock,
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Start Pull early'));
    expect(taps, ['early']);
  });

  testWidgets('without step access the walk row opens the Steps page', (
    tester,
  ) async {
    await pumpComponent(tester, card(steps: null));

    expect(find.text('Go for a walk'), findsNothing);
    await tester.tap(find.text('See your steps'));
    expect(taps, ['steps']);
  });

  testWidgets('a reached goal shows the steps against it', (tester) async {
    await pumpComponent(tester, card(steps: 10240));

    expect(find.text('Step goal reached'), findsOneWidget);
    expect(find.text('10,240 of 10,000 steps today'), findsOneWidget);
  });
}
