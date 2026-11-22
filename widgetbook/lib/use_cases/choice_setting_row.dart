import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/choice_sheet.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

const _effort = [
  ('Off', null),
  ('By feel (default)', 'Easy, moderate, hard or max'),
  ('RIR · reps in reserve', '0, 1, 2, 3 or 4+ reps left'),
  ('RPE · rated effort', 'From 6 or less up to 10'),
];

@widgetbook.UseCase(name: 'Choice sheet', type: ChoiceSettingRow)
Widget choiceSettingRow(BuildContext context) => Padding(
  padding: const EdgeInsets.all(Gap.md),
  child: ListRowCard(
    children: [
      ChoiceSettingRow<int>(
        title: 'Effort question',
        subtitle: 'Asked after each set you log.',
        values: [for (var i = 0; i < _effort.length; i++) i],
        selected: 1,
        labelOf: (i) => _effort[i].$1,
        detailOf: (i) => _effort[i].$2,
        onChanged: (_) {},
      ),
    ],
  ),
);
