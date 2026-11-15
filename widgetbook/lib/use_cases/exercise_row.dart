import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/exercise_row.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _card(List<Widget> rows) => Padding(
  padding: const EdgeInsets.all(Gap.md),
  child: ListRowCard(children: rows),
);

@widgetbook.UseCase(name: 'Library', type: ExerciseRow)
Widget libraryRows(BuildContext context) => _card([
  ExerciseRow(
    name: context.knobs.string(label: 'Name', initialValue: 'Bench Press'),
    detail: 'Chest · Barbell',
    favorite: context.knobs.boolean(label: 'Favourite'),
    onFavorite: () {},
    onTap: () {},
  ),
  ExerciseRow(
    name: 'Incline Dumbbell Press',
    detail: 'Chest · Dumbbell',
    favorite: true,
    onFavorite: () {},
    onTap: () {},
  ),
  ExerciseRow(
    name: 'Cable Hip Abduction',
    detail: 'Glutes · Cable',
    custom: true,
    onFavorite: () {},
    onTap: () {},
  ),
  ExerciseRow(
    name: 'Pull-up',
    detail: 'Back · Bodyweight',
    onFavorite: () {},
    onTap: () {},
  ),
]);

@widgetbook.UseCase(name: 'Picker', type: ExerciseRow)
Widget pickerRows(BuildContext context) => SingleChildScrollView(
  padding: const EdgeInsets.all(Gap.md),
  child: Column(
    spacing: Gap.sm,
    children: [
      ListRowCard(
        children: [
          for (final (name, detail, selected) in [
            ('Bench Press', 'Chest · Barbell', true),
            ('Incline Dumbbell Press', 'Chest · Dumbbell', true),
            ('Cable Fly', 'Chest · Cable', true),
            ('Push-up', 'Chest · Bodyweight', false),
          ])
            ExerciseRow.pick(
              name: name,
              detail: detail,
              selected: selected,
              onTap: () {},
            ),
        ],
      ),
      ForgeButton(
        label: 'Add 3 exercises',
        size: ForgeButtonSize.large,
        onPressed: () {},
      ),
    ],
  ),
);

@widgetbook.UseCase(name: 'Picker at the limit', type: ExerciseRow)
Widget pickerFullRows(BuildContext context) => _card([
  for (final (name, detail, selected) in [
    ('Bench Press', 'Chest · Barbell', true),
    ('Incline Dumbbell Press', 'Chest · Dumbbell', true),
    ('Cable Fly', 'Chest · Cable', false),
    ('Push-up', 'Chest · Bodyweight', false),
  ])
    ExerciseRow.pick(
      name: name,
      detail: detail,
      selected: selected,
      enabled: selected,
      onTap: () {},
    ),
]);

@widgetbook.UseCase(name: 'Similar exercises', type: ExerciseRow)
Widget similarRows(BuildContext context) => _card([
  ExerciseRow(
    name: 'Dumbbell Bench Press',
    detail: 'Chest · Dumbbell',
    relation: 'Alternative',
    onTap: () {},
  ),
  ExerciseRow(
    name: 'Machine Chest Press',
    detail: 'Chest · Machine',
    relation: 'Alternative',
    onTap: () {},
  ),
  ExerciseRow(
    name: 'Incline Bench Press',
    detail: 'Chest · Barbell',
    relation: 'Variation',
    onTap: () {},
  ),
]);
