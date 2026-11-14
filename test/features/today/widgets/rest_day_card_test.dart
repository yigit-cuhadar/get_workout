import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/today/presentation/widgets/rest_day_card.dart';

import '../../../core/widgets/component_harness.dart';

void main() {
  final taps = <String>[];

  RestDayCard card({required int? steps}) => RestDayCard(
    next: 'Pull, Mon, Nov 16',
    steps: steps,
    goal: 10000,
    onSteps: () => taps.add('steps'),
    onLogCardio: () => taps.add('cardio'),
    onStartEmpty: () => taps.add('empty'),
  );

  setUp(taps.clear);

  testWidgets('offers a walk toward the goal, cardio and an empty workout', (
    tester,
  ) async {
    await pumpComponent(tester, card(steps: 6240));

    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('Next: Pull, Mon, Nov 16'), findsOneWidget);
    expect(find.text('3,760 steps to your goal'), findsOneWidget);

    await tester.tap(find.text('Go for a walk'));
    await tester.tap(find.text('Log cardio'));
    await tester.tap(find.text('Start empty workout'));
    expect(taps, ['steps', 'cardio', 'empty']);
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
