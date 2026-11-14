import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/featured_card.dart';

import 'component_harness.dart';

void main() {
  ForgeButtonVariant variantOf(WidgetTester tester, String label) => tester
      .widget<ForgeButton>(find.widgetWithText(ForgeButton, label))
      .variant;

  testWidgets('a block starts from its featured button and opens on a tap', (
    tester,
  ) async {
    var started = 0;
    var opened = 0;
    await pumpComponent(
      tester,
      FeaturedCard(
        form: FeaturedCardForm.block,
        eyebrow: 'Push Pull Legs',
        title: 'Push',
        line: const FeaturedLine('6 exercises · ~55 min', data: 'Fri, Nov 13'),
        action: FeaturedAction('Start Push', () => started++),
        onTap: () => opened++,
      ),
    );

    expect(find.text('Fri, Nov 13'), findsOneWidget);
    expect(variantOf(tester, 'Start Push'), ForgeButtonVariant.featured);
    expect(find.byType(ForgeIcon), findsNWidgets(2));

    await tester.tap(find.text('Start Push'));
    expect((started, opened), (1, 0));

    await tester.tap(find.text('Push'));
    expect((started, opened), (1, 1));
  });

  testWidgets('a summary block has four stats and no chevron', (tester) async {
    await pumpComponent(
      tester,
      const FeaturedCard(
        form: FeaturedCardForm.block,
        eyebrow: 'Workout done',
        title: 'Push',
        stats: [
          FeaturedStat('Duration', '52 min'),
          FeaturedStat('Volume', '12,400 kg'),
          FeaturedStat('Working sets', '18'),
          FeaturedStat('Exercises', '6'),
        ],
      ),
    );

    for (final text in ['Duration', '52 min', 'Exercises', '6']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.byType(ForgeIcon), findsNothing);
    expect(find.byType(ForgeButton), findsNothing);
  });

  testWidgets('a locked copy shows a lock and keeps Start tappable', (
    tester,
  ) async {
    var started = 0;
    await pumpComponent(
      tester,
      FeaturedCard(
        form: FeaturedCardForm.block,
        eyebrow: 'Upper Lower Strength',
        locked: true,
        title: 'Upper',
        note: 'Premium has ended.',
        action: FeaturedAction('Start Upper', () => started++, locked: true),
      ),
    );

    final button = tester.widget<ForgeButton>(find.byType(ForgeButton));
    expect(button.locked, isTrue);
    expect(find.text('Premium has ended.'), findsOneWidget);

    await tester.tap(find.text('Start Upper'));
    expect(started, 1);
  });

  testWidgets('a missed day puts Do it today over Move and Skip', (
    tester,
  ) async {
    final taps = <String>[];
    await pumpComponent(
      tester,
      FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: 'Active program · week 3 of 8',
        title: 'Push Pull Legs',
        line: const FeaturedLine.missed(
          'You missed Legs on Wed, Nov 11',
          status: 'Missed',
        ),
        action: FeaturedAction('Do it today', () => taps.add('today')),
        moreActions: [
          FeaturedAction('Move to Saturday', () => taps.add('move')),
          FeaturedAction('Skip', () => taps.add('skip')),
        ],
      ),
    );

    expect(variantOf(tester, 'Do it today'), ForgeButtonVariant.primary);
    expect(variantOf(tester, 'Skip'), ForgeButtonVariant.secondary);
    final today = tester.getRect(find.text('Do it today'));
    final move = tester.getRect(find.text('Move to Saturday'));
    final skip = tester.getRect(find.text('Skip'));
    expect(move.top, greaterThan(today.bottom));
    expect(move.top, skip.top);

    for (final label in ['Do it today', 'Move to Saturday', 'Skip']) {
      await tester.tap(find.text(label));
    }
    expect(taps, ['today', 'move', 'skip']);
  });

  testWidgets('an outline with two actions puts them side by side', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      FeaturedCard(
        form: FeaturedCardForm.outline,
        eyebrow: 'Recommended for you · free',
        title: 'Push Pull Legs',
        action: FeaturedAction('Start this program', () {}),
        moreActions: [FeaturedAction('Browse', () {})],
      ),
    );

    expect(
      tester.getRect(find.text('Start this program')).top,
      tester.getRect(find.text('Browse')).top,
    );
    expect(variantOf(tester, 'Browse'), ForgeButtonVariant.secondary);
  });

  testWidgets('loading shows the eyebrow over shimmering bars, no button', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const FeaturedCard.loading(eyebrow: 'Next workout'),
    );

    expect(find.text('Next workout'), findsOneWidget);
    expect(find.byType(SkeletonBar), findsNWidgets(2));
    expect(find.byType(ForgeButton), findsNothing);
  });
}
