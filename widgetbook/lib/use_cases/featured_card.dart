import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/featured_card.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _page(Widget child) =>
    SingleChildScrollView(padding: const EdgeInsets.all(Gap.md), child: child);

@widgetbook.UseCase(name: 'Block', type: FeaturedCard)
Widget featuredBlock(BuildContext context) => _page(
  FeaturedCard(
    form: FeaturedCardForm.block,
    eyebrow: context.knobs.string(
      label: 'Eyebrow',
      initialValue: 'Push Pull Legs',
    ),
    title: context.knobs.string(label: 'Title', initialValue: 'Push'),
    line: const FeaturedLine('6 exercises · ~55 min', data: 'Fri, Nov 13'),
    action: FeaturedAction('Start Push', () {}),
    onTap: () {},
  ),
);

@widgetbook.UseCase(name: 'Accent outline', type: FeaturedCard)
Widget featuredOutline(BuildContext context) => _page(
  FeaturedCard(
    form: FeaturedCardForm.outline,
    eyebrow: 'Recommended for you · free',
    title: 'Push Pull Legs',
    line: const FeaturedLine(
      '3 days · Intermediate · 8 weeks',
      data: '~55 min',
    ),
    action: FeaturedAction('Start this program', () {}),
    onTap: () {},
  ),
);

@widgetbook.UseCase(name: 'Header band', type: FeaturedCard)
Widget featuredBand(BuildContext context) => _page(
  FeaturedCard(
    form: FeaturedCardForm.band,
    eyebrow: 'Active program · week 3 of 8',
    title: 'Push Pull Legs',
    line: const FeaturedLine('Next: Pull, Mon, Nov 16', data: '37%'),
    action: FeaturedAction('Start Pull', () {}),
    onTap: () {},
  ),
);

@widgetbook.UseCase(name: 'Running block', type: FeaturedCard)
Widget featuredRunning(BuildContext context) => _page(
  FeaturedCard(
    form: FeaturedCardForm.block,
    eyebrow: 'Workout in progress',
    title: 'Push',
    line: const FeaturedLine('Exercise 1 of 6 · 3 sets done', data: '24:16'),
    action: FeaturedAction('Resume workout', () {}),
    onTap: () {},
  ),
);

@widgetbook.UseCase(name: 'Summary block', type: FeaturedCard)
Widget featuredSummary(BuildContext context) => _page(
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

@widgetbook.UseCase(name: 'Locked premium copy', type: FeaturedCard)
Widget featuredLocked(BuildContext context) => _page(
  FeaturedCard(
    form: FeaturedCardForm.block,
    eyebrow: 'Upper Lower Strength · Premium',
    locked: true,
    title: 'Upper',
    line: const FeaturedLine('6 exercises · ~70 min', data: 'Mon, Nov 16'),
    note: 'Premium has ended. Your program is kept; Start opens Premium.',
    action: FeaturedAction('Start Upper', () {}, locked: true),
    onTap: () {},
  ),
);

@widgetbook.UseCase(name: 'Loading', type: FeaturedCard)
Widget featuredLoading(BuildContext context) =>
    _page(const FeaturedCard.loading(eyebrow: 'Next workout'));

@widgetbook.UseCase(name: 'Band · missed day', type: FeaturedCard)
Widget featuredMissed(BuildContext context) => _page(
  FeaturedCard(
    form: FeaturedCardForm.band,
    eyebrow: 'Active program · week 3 of 8',
    title: 'Push Pull Legs',
    line: const FeaturedLine.missed(
      'You missed Legs on Wed, Nov 11',
      status: 'Missed',
    ),
    action: FeaturedAction('Do it today', () {}),
    moreActions: [
      FeaturedAction('Move to Saturday', () {}),
      FeaturedAction('Skip', () {}),
    ],
    onTap: () {},
  ),
);

@widgetbook.UseCase(name: 'Band · finished', type: FeaturedCard)
Widget featuredFinished(BuildContext context) => _page(
  FeaturedCard(
    form: FeaturedCardForm.band,
    eyebrow: 'Finished · 8 of 8 weeks',
    title: 'Push Pull Legs',
    line: const FeaturedLine('24 workouts · Bench Press e1RM +9 kg'),
    action: FeaturedAction('Run it again', () {}),
    moreActions: [FeaturedAction('New program', () {})],
    onTap: () {},
  ),
);

@widgetbook.UseCase(name: 'Band · empty', type: FeaturedCard)
Widget featuredEmpty(BuildContext context) => _page(
  FeaturedCard(
    form: FeaturedCardForm.band,
    eyebrow: 'Cardio · this week',
    title: 'No sessions yet',
    note: 'Log a run, ride or swim to see your weeks here.',
    action: FeaturedAction('Log cardio', () {}),
    onTap: () {},
  ),
);

@widgetbook.UseCase(name: 'Outline · two actions', type: FeaturedCard)
Widget featuredOutlineTwo(BuildContext context) => _page(
  FeaturedCard(
    form: FeaturedCardForm.outline,
    eyebrow: 'Recommended for you · free',
    title: 'Push Pull Legs',
    line: const FeaturedLine(
      '3 days · Intermediate · 8 weeks',
      data: '~55 min',
    ),
    action: FeaturedAction('Start this program', () {}),
    moreActions: [FeaturedAction('Browse', () {})],
    onTap: () {},
  ),
);
