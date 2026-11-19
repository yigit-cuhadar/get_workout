import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/programs/presentation/training_days_sheet.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

/// The sheet on a sheet's surface, as tall as a phone allows.
Widget _sheet(
  BuildContext context, {
  required List<String> dayNames,
  required Map<int, int> initial,
}) => ColoredBox(
  color: ForgeStyle.of(context).colors.surface,
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 390, maxHeight: 760),
    child: TrainingDaysSheet(
      dayNames: dayNames,
      initial: initial,
      firstWeekday: DateTime.monday,
      confirmLabel: 'Save',
    ),
  ),
);

@widgetbook.UseCase(name: 'Two days on four weekdays', type: TrainingDaysSheet)
Widget trainingDaysAb(BuildContext context) => _sheet(
  context,
  dayNames: const ['Item title A', 'Item title B'],
  initial: const {1: 0, 2: 1, 4: 0, 5: 1},
);

@widgetbook.UseCase(name: 'Seven long day names', type: TrainingDaysSheet)
Widget trainingDaysLong(BuildContext context) => _sheet(
  context,
  dayNames: [
    for (var i = 1; i <= 7; i++)
      'Day $i · Heavy compound strength and accessory volume work',
  ],
  initial: {
    for (var weekday = 1; weekday <= 7; weekday++) weekday: weekday - 1,
  },
);

@widgetbook.UseCase(name: 'No day picked (Save off)', type: TrainingDaysSheet)
Widget trainingDaysNone(BuildContext context) => _sheet(
  context,
  dayNames: const ['Item title A', 'Item title B', 'Item title C'],
  initial: const {},
);
