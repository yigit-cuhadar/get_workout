import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/choice_sheet.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

@widgetbook.UseCase(name: 'Choice sheet rows', type: ChoiceRow)
Widget choiceRows(BuildContext context) {
  final selected = context.knobs.int.slider(
    label: 'Selected',
    initialValue: 1,
    max: 3,
  );
  return Padding(
    padding: const EdgeInsets.all(Gap.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (label, detail)) in const [
          ('Off', null),
          ('By feel (default)', 'Easy, moderate, hard or max'),
          ('RIR · reps in reserve', '0, 1, 2, 3 or 4+ reps left'),
          ('RPE · rated effort', 'From 6 or less up to 10'),
        ].indexed)
          ChoiceRow(
            label: label,
            detail: detail,
            selected: i == selected,
            onTap: () {},
          ),
      ],
    ),
  );
}
