import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/choice_sheet.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Choice sheet rows', type: ChoiceRow)
Widget choiceRows(BuildContext context) {
  final selected = context.knobs.int.slider(
    label: 'Selected',
    initialValue: 0,
    max: 3,
  );
  return Padding(
    padding: const EdgeInsets.all(Gap.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, label) in const [
          'By feel (default)',
          'Reps in reserve (RIR)',
          'RPE (1-10)',
          'Off',
        ].indexed)
          ChoiceRow(label: label, selected: i == selected, onTap: () {}),
      ],
    ),
  );
}
