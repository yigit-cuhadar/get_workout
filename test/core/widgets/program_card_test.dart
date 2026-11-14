import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/program_card.dart';

import 'component_harness.dart';

void main() {
  testWidgets('a card shows its facts and goal and opens on a tap', (
    tester,
  ) async {
    var opened = 0;
    await pumpComponent(
      tester,
      ProgramCard(
        name: 'Push Pull Legs',
        facts: '3 days a week · Intermediate · 8 weeks',
        tags: const ['Build muscle'],
        onTap: () => opened++,
      ),
    );

    expect(find.widgetWithText(ForgeTag, 'Build muscle'), findsOneWidget);
    expect(find.text('Premium'), findsNothing);
    expect(find.text('Recommended for you'), findsNothing);

    await tester.tap(find.text('Push Pull Legs'));
    expect(opened, 1);
  });

  testWidgets('a locked card carries the Premium tag', (tester) async {
    await pumpComponent(
      tester,
      ProgramCard(
        name: 'Upper Lower Strength',
        facts: '4 days a week · Advanced · 12 weeks',
        locked: true,
        onTap: () {},
      ),
    );

    final tag = tester.widget<ForgeTag>(
      find.widgetWithText(ForgeTag, 'Premium'),
    );
    expect(tag.kind, ForgeTagKind.premium);
  });

  testWidgets('a recommended card says why it matches', (tester) async {
    await pumpComponent(
      tester,
      ProgramCard(
        name: 'Push Pull Legs',
        facts: '3 days a week · Intermediate · ~55 min',
        recommended: true,
        match: 'Matches your goal and days',
        onTap: () {},
      ),
    );

    expect(find.text('Recommended for you'), findsOneWidget);
    expect(find.text('Matches your goal and days'), findsOneWidget);
  });

  testWidgets('a row carries Fits you, Premium or the eyebrow', (tester) async {
    var opened = 0;
    await pumpComponent(
      tester,
      ProgramCard.row(
        name: 'Push Pull Legs',
        facts: '3 days · Intermediate · 8 weeks',
        fits: true,
        recommended: true,
        onTap: () => opened++,
      ),
    );

    final fits = tester.widget<ForgeTag>(
      find.widgetWithText(ForgeTag, 'Fits you'),
    );
    expect(fits.kind, ForgeTagKind.record);
    expect(find.text('Recommended for you'), findsOneWidget);

    await tester.tap(find.text('Push Pull Legs'));
    expect(opened, 1);
  });
}
