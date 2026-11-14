import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/program_card.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _page(List<Widget> children) => SingleChildScrollView(
  padding: const EdgeInsets.all(Gap.md),
  child: Column(spacing: 10, children: children),
);

@widgetbook.UseCase(name: 'Free and Premium', type: ProgramCard)
Widget programCards(BuildContext context) => _page([
  ProgramCard(
    name: 'Push Pull Legs',
    facts: '3 days a week · Intermediate · 8 weeks',
    tags: const ['Build muscle'],
    onTap: () {},
  ),
  ProgramCard(
    name: 'Upper Lower Strength',
    facts: '4 days a week · Advanced · 12 weeks',
    tags: const ['Get stronger'],
    locked: context.knobs.boolean(label: 'Locked', initialValue: true),
    onTap: () {},
  ),
]);

@widgetbook.UseCase(name: 'Row', type: ProgramCard)
Widget programRows(BuildContext context) => _page([
  ListRowCard(
    children: [
      ProgramCard.row(
        name: 'Push Pull Legs',
        facts: '3 days · Intermediate · 8 weeks',
        fits: true,
        onTap: () {},
      ),
      ProgramCard.row(
        name: 'Upper Lower Strength',
        facts: '4 days · Advanced · 12 weeks',
        locked: true,
        onTap: () {},
      ),
    ],
  ),
]);

@widgetbook.UseCase(name: 'Recommended for you · card', type: ProgramCard)
Widget programRecommended(BuildContext context) => _page([
  ProgramCard(
    name: 'Push Pull Legs',
    facts: '3 days a week · Intermediate · ~55 min',
    tags: const ['Build muscle', '8 weeks'],
    recommended: true,
    match: 'Matches your goal and days',
    onTap: () {},
  ),
]);

@widgetbook.UseCase(name: 'Recommended for you · rows', type: ProgramCard)
Widget programRecommendedRows(BuildContext context) => _page([
  ListRowCard(
    children: [
      ProgramCard.row(
        name: 'Push Pull Legs',
        facts: '3 days · Intermediate · 8 weeks',
        recommended: true,
        onTap: () {},
      ),
      ProgramCard.row(
        name: 'Full Body Basics',
        facts: '3 days · Beginner · 6 weeks',
        recommended: true,
        onTap: () {},
      ),
    ],
  ),
]);
