import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/featured_card.dart';

import '../../component_harness.dart';

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

  testWidgets('an odd last stat keeps its column', (tester) async {
    await pumpComponent(
      tester,
      const FeaturedCard(
        form: FeaturedCardForm.block,
        eyebrow: 'Workout done',
        title: 'Push',
        stats: [
          FeaturedStat('Duration', '52 min'),
          FeaturedStat('Volume', '12,400 kg'),
          FeaturedStat('Exercises', '6'),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('Exercises')).dx,
      tester.getTopLeft(find.text('Duration')).dx,
    );
    double column(String label) => tester
        .getSize(
          find
              .ancestor(of: find.text(label), matching: find.byType(Expanded))
              .first,
        )
        .width;
    expect(column('Exercises'), column('Duration'));
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

  testWidgets('a prompt stacks every button, a locked one keeping its lock', (
    tester,
  ) async {
    final taps = <String>[];
    await pumpComponent(
      tester,
      FeaturedCard(
        form: FeaturedCardForm.prompt,
        eyebrow: 'Get started',
        title: 'Pick your first program',
        note: 'A plan sets your training days and fills Today.',
        action: FeaturedAction('See ready-made programs', () => taps.add('a')),
        moreActions: [
          FeaturedAction(
            'Generate a program',
            () => taps.add('b'),
            locked: true,
          ),
          FeaturedAction('Start empty workout', () => taps.add('c')),
        ],
      ),
    );

    expect(
      variantOf(tester, 'See ready-made programs'),
      ForgeButtonVariant.primary,
    );
    expect(
      variantOf(tester, 'Start empty workout'),
      ForgeButtonVariant.secondary,
    );
    final labels = [
      'See ready-made programs',
      'Generate a program',
      'Start empty workout',
    ];
    for (var i = 1; i < labels.length; i++) {
      expect(
        tester.getRect(find.text(labels[i])).top,
        greaterThan(tester.getRect(find.text(labels[i - 1])).bottom),
      );
    }
    expect(
      tester
          .widget<ForgeButton>(
            find.widgetWithText(ForgeButton, 'Generate a program'),
          )
          .locked,
      isTrue,
    );
    expect(
      find.byType(ForgeIcon).evaluate().where((e) {
        final icon = e.widget as ForgeIcon;
        return icon.icon == ForgeIcons.chevronRight;
      }),
      isEmpty,
    );
    for (final label in labels) {
      await tester.tap(find.text(label));
    }
    expect(taps, ['a', 'b', 'c']);
  });

  testWidgets('a band shows its progress, its rows and its menu', (
    tester,
  ) async {
    final taps = <String>[];
    await pumpComponent(
      tester,
      FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: 'Active program · week 3 of 8',
        title: 'Push Pull Legs',
        progress: 0.37,
        action: FeaturedAction('Start Legs', () => taps.add('start')),
        menu: IconButton(
          tooltip: 'Program options',
          onPressed: () => taps.add('menu'),
          icon: const ForgeIcon(ForgeIcons.moreHoriz),
        ),
        rows: [
          ListRow(title: 'Pull', detail: 'Done', onTap: () => taps.add('pull')),
          const ListRow(title: 'Legs', detail: 'Missed'),
        ],
      ),
    );

    expect(tester.widget<Progress>(find.byType(Progress)).value, 0.37);
    expect(
      tester.getRect(find.text('Pull')).top,
      greaterThan(tester.getRect(find.text('Start Legs')).bottom),
    );
    // A line above each row.
    expect(find.byType(Divider), findsNWidgets(2));
    await tester.tap(find.byTooltip('Program options'));
    await tester.tap(find.text('Start Legs'));
    await tester.tap(find.text('Pull'));
    expect(taps, ['menu', 'start', 'pull']);
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

  testWidgets('a prompt tones its title and stacks only secondary buttons '
      'without a main action', (tester) async {
    var managed = 0;
    await pumpComponent(
      tester,
      FeaturedCard(
        form: FeaturedCardForm.prompt,
        eyebrow: 'GetWorkout Premium',
        title: 'Payment problem. Update your payment method',
        titleTone: FeaturedTitleTone.danger,
        note: 'Program generator, 19 more programs and charts.',
        moreActions: [FeaturedAction('Manage subscription', () => managed++)],
      ),
    );
    final colors = ForgeStyle.of(tester.element(find.byType(FeaturedCard)))
        .colors;

    expect(
      tester
          .widget<Text>(
            find.text('Payment problem. Update your payment method'),
          )
          .style!
          .color,
      colors.danger,
    );
    expect(find.byType(ForgeButton), findsOneWidget);
    expect(
      variantOf(tester, 'Manage subscription'),
      ForgeButtonVariant.secondary,
    );
    await tester.tap(find.text('Manage subscription'));
    expect(managed, 1);
  });

  testWidgets('a muted prompt title shows a state not known yet', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const FeaturedCard(
        form: FeaturedCardForm.prompt,
        eyebrow: 'GetWorkout Premium',
        title: 'Checking…',
        titleTone: FeaturedTitleTone.muted,
      ),
    );
    final colors = ForgeStyle.of(tester.element(find.byType(FeaturedCard)))
        .colors;

    expect(
      tester.widget<Text>(find.text('Checking…')).style!.color,
      colors.inkMuted,
    );
    expect(find.byType(ForgeButton), findsNothing);
  });
}
