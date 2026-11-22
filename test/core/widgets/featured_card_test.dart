import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/featured_card.dart';

import '../../component_harness.dart';

void main() {
  ForgeButtonVariant variantOf(WidgetTester tester, String label) => tester
      .widget<ForgeButton>(find.widgetWithText(ForgeButton, label))
      .variant;

  testWidgets('an outline carries the Premium tag under its title', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const FeaturedCard(
        form: FeaturedCardForm.outline,
        eyebrow: 'Recommended for you',
        title: 'Upper Lower Strength',
        premiumTag: 'Premium',
        line: FeaturedLine('4 days · Intermediate · 12 weeks'),
      ),
    );

    final tag = find.widgetWithText(ForgeTag, 'Premium');
    expect(tester.widget<ForgeTag>(tag).kind, ForgeTagKind.premium);
    expect(
      tester.getTopLeft(tag).dy,
      greaterThan(tester.getTopLeft(find.text('Upper Lower Strength')).dy),
    );
  });

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

  testWidgets('a band with a menu and a tap opens on a tap, menu in place '
      'of the chevron', (tester) async {
    final taps = <String>[];
    await pumpComponent(
      tester,
      FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: 'Active program · week 3 of 8',
        title: 'Push Pull Legs',
        menu: IconButton(
          tooltip: 'Program options',
          onPressed: () => taps.add('menu'),
          icon: const ForgeIcon(ForgeIcons.moreHoriz),
        ),
        onTap: () => taps.add('open'),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (w) => w is ForgeIcon && w.icon == ForgeIcons.chevronRight,
      ),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Program options'));
    await tester.tap(find.text('Push Pull Legs'));
    expect(taps, ['menu', 'open']);
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

  testWidgets('a band holds its chart between its line and its buttons', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: 'Body',
        title: '82.4 kg',
        line: const FeaturedLine(
          '−0.4 since Nov 8',
          data: '19.5 % fat',
          icon: ForgeIcons.trendingUp,
        ),
        chart: const SizedBox(key: Key('chart'), height: 32),
        action: FeaturedAction('Log weight', () {}),
        moreActions: [FeaturedAction('Measurement day', () {})],
        onTap: () {},
      ),
    );

    final chart = tester.getRect(find.byKey(const Key('chart')));
    expect(
      chart.top,
      greaterThan(tester.getRect(find.text('19.5 % fat')).bottom),
    );
    expect(chart.bottom, lessThan(tester.getRect(find.text('Log weight')).top));
    expect(
      tester.widgetList<ForgeIcon>(find.byType(ForgeIcon)).map((i) => i.icon),
      contains(ForgeIcons.trendingUp),
    );
  });

  testWidgets('a band that failed shows the eyebrow, Retry and its buttons', (
    tester,
  ) async {
    final taps = <String>[];
    await pumpComponent(
      tester,
      FeaturedCard.bandError(
        eyebrow: 'Body',
        error: FeaturedError(
          "Couldn't load your entries",
          retryLabel: 'Retry',
          onRetry: () => taps.add('retry'),
        ),
        action: FeaturedAction('Log weight', () => taps.add('log')),
        moreActions: [FeaturedAction('Measurement day', () {})],
        onTap: () => taps.add('open'),
      ),
    );

    expect(find.text("Couldn't load your entries"), findsOneWidget);
    expect(variantOf(tester, 'Retry'), ForgeButtonVariant.outline);
    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Log weight'));
    await tester.tap(find.text('Body'));
    expect(taps, ['retry', 'log', 'open']);
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
        note: 'Program generator, 23 more programs and charts.',
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

  testWidgets('a past workout band: its origin opens it, four figures', (
    tester,
  ) async {
    var opened = 0;
    await pumpComponent(
      tester,
      FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: 'Fri, Nov 13 · 18:05',
        title: 'Push',
        origin: 'Push Pull Legs · week 3',
        onOrigin: () => opened++,
        stats: const [
          FeaturedStat('duration', '52 min'),
          FeaturedStat('volume', '12,400 kg'),
          FeaturedStat('sets', '18'),
          FeaturedStat('records', '2'),
        ],
      ),
    );

    for (final text in ['52 min', '12,400 kg', '18', '2', 'records']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(
      tester
          .widget<Text>(find.text('Push Pull Legs · week 3'))
          .style!
          .decoration,
      TextDecoration.underline,
    );
    await tester.tap(find.text('Push Pull Legs · week 3'));
    expect(opened, 1);
  });

  testWidgets('an origin with nothing to open is plain', (tester) async {
    await pumpComponent(
      tester,
      const FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: 'Fri, Nov 13 · 18:05',
        title: 'Push',
        origin: 'From a program you deleted',
      ),
    );
    expect(
      tester
          .widget<Text>(find.text('From a program you deleted'))
          .style!
          .decoration,
      isNot(TextDecoration.underline),
    );
  });

  testWidgets('a loading band shimmers four figures', (tester) async {
    await pumpComponent(tester, const FeaturedCard.bandLoading());
    expect(find.byType(SkeletonBar), findsNWidgets(4));
  });

  testWidgets('the target form: a 15px title, a muted line, the accent '
      'outline and no button', (tester) async {
    await pumpComponent(
      tester,
      const FeaturedCard.target(
        title: 'Target 78 kg',
        note: 'At this pace, around Dec 28.',
      ),
    );
    final colors = ForgeStyle.of(tester.element(find.byType(FeaturedCard)))
        .colors;

    expect(tester.widget<Text>(find.text('Target 78 kg')).style!.fontSize, 15);
    expect(
      tester
          .widget<Text>(find.text('At this pace, around Dec 28.'))
          .style!
          .color,
      colors.inkMuted,
    );
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(FeaturedCard),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      ((box.decoration as BoxDecoration).border! as Border).top.color,
      colors.accent,
    );
    expect(find.byType(ForgeButton), findsNothing);
  });

  testWidgets('a band sets its aside beside the title and its week over a '
      'bar in parts', (tester) async {
    await pumpComponent(
      tester,
      FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: 'Active program',
        title: '82.4 kg',
        titleAside: '−2.1 kg in 12 weeks',
        when: '18 % body fat · Nov 14',
        progress: 0.25,
        progressSegments: 4,
        progressLabel: 'Week 1 of 4',
        progressDetail: '1 of 3 days this week',
        onTap: () {},
      ),
    );

    final title = find.textContaining('82.4 kg');
    expect(title, findsOneWidget);
    expect(find.textContaining('−2.1 kg in 12 weeks'), findsOneWidget);
    expect(find.text('18 % body fat · Nov 14'), findsOneWidget);
    expect(find.text('Week 1 of 4'), findsOneWidget);
    expect(find.text('1 of 3 days this week'), findsOneWidget);
    expect(tester.widget<Progress>(find.byType(Progress)).segments, 4);
  });

  testWidgets('a summary stat sets its change under the value', (tester) async {
    await pumpComponent(
      tester,
      const FeaturedCard(
        form: FeaturedCardForm.block,
        eyebrow: 'Workout done · Today',
        title: 'Push',
        stats: [FeaturedStat('Duration', '1 h 12 min', change: '+8 min')],
      ),
    );

    expect(
      tester.getTopLeft(find.text('+8 min')).dy,
      greaterThan(tester.getBottomLeft(find.text('1 h 12 min')).dy - 1),
    );
  });

  testWidgets('a name keeps one line: it shrinks to 18 px, then ends in …', (
    tester,
  ) async {
    Text titleOf(String name) => tester.widget<Text>(find.textContaining(name));
    Future<void> pump(String name) => pumpComponent(
      tester,
      FeaturedCard(form: FeaturedCardForm.block, eyebrow: 'Today', title: name),
    );

    await pump('Push');
    final normal = titleOf('Push');
    final normalSize = normal.style!.fontSize!;
    final lineHeight = tester.getSize(find.text('Push')).height;

    await pump('Upper Lower 4');
    final shrunk = titleOf('Upper Lower 4');
    expect(shrunk.style!.fontSize, lessThan(normalSize));
    expect(shrunk.style!.fontSize, greaterThan(18));
    expect(tester.getSize(find.text('Upper Lower 4')).height, lineHeight);

    await pump('Gym Starter: Full Body 3-Day');
    final cut = titleOf('Gym Starter: Full Body 3-Day');
    expect(cut.style!.fontSize, 18);
    expect((cut.maxLines, cut.overflow), (1, TextOverflow.ellipsis));
    expect(
      tester.getSize(find.text('Gym Starter: Full Body 3-Day')).height,
      lineHeight,
    );
  });

  testWidgets('a value beside the name is never cut; the name gives way', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: 'Body weight',
        title: 'A body weight name far too long for one line',
        titleAside: '−2.1 kg in 12 weeks',
      ),
    );

    final name = tester.widget<Text>(
      find.text('A body weight name far too long for one line'),
    );
    expect(name.style!.fontSize, 18);
    expect(name.overflow, TextOverflow.ellipsis);
    final aside = find.text('−2.1 kg in 12 weeks');
    final painter = TextPainter(
      text: TextSpan(
        text: '−2.1 kg in 12 weeks',
        style: tester.widget<Text>(aside).style,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(tester.getSize(aside).width, closeTo(painter.width, 0.5));
    painter.dispose();
    expect(
      tester.getTopRight(aside).dx,
      lessThanOrEqualTo(tester.getTopRight(find.byType(FeaturedCard)).dx),
    );
  });
}
