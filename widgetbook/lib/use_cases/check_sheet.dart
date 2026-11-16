import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/check_sheet.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

const _equipment = [
  'Barbell',
  'EZ bar',
  'Trap bar',
  'Dumbbell',
  'Kettlebell',
  'Weight plate',
  'Cable',
  'Machine',
  'Smith machine',
  'Bench',
  'Box or step',
  'Back extension bench',
  'Pull-up bar',
  'Dip station',
  'Resistance band',
];

@widgetbook.UseCase(name: 'Ticked and not', type: CheckRow)
Widget checkRows(BuildContext context) {
  final ticked = context.knobs.boolean(
    label: 'First ticked',
    initialValue: true,
  );
  return Padding(
    padding: const EdgeInsets.all(Gap.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckRow(label: 'Barbell', checked: ticked, onChanged: (_) {}),
        const Divider(),
        CheckRow(label: 'EZ bar', checked: !ticked, onChanged: (_) {}),
      ],
    ),
  );
}

@widgetbook.UseCase(name: 'With a subtitle, scrolling', type: CheckSheet)
Widget checkSheetLong(BuildContext context) => _OnSurface(
  child: CheckSheet<String>(
    title: 'My equipment',
    subtitle: 'Bodyweight exercises are always included.',
    values: _equipment,
    initial: const {'Barbell', 'Dumbbell', 'Weight plate', 'Bench'},
    labelOf: (item) => item,
    saveLabel: 'Save',
  ),
);

@widgetbook.UseCase(name: 'Short, nothing ticked', type: CheckSheet)
Widget checkSheetShort(BuildContext context) => _OnSurface(
  child: CheckSheet<String>(
    title: 'Level',
    values: const ['Beginner', 'Intermediate', 'Advanced'],
    initial: const {},
    labelOf: (level) => level,
    saveLabel: 'Save',
  ),
);

/// The sheet at the bottom, on the surface a sheet is drawn on.
class _OnSurface extends StatelessWidget {
  const _OnSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Material(color: ForgeStyle.of(context).colors.surface, child: child),
  );
}
