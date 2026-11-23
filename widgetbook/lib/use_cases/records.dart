import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/records.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _page(List<Widget> children) => SingleChildScrollView(
  padding: const EdgeInsets.all(Gap.md),
  child: Column(spacing: 10, children: children),
);

@widgetbook.UseCase(name: 'Biggest record', type: RecordHighlight)
Widget biggestRecord(BuildContext context) => _page([
  RecordHighlight(
    value: context.knobs.string(label: 'Value', initialValue: '82.5 kg × 8'),
    line: 'Bench Press · e1RM 104 kg · +2.5 kg',
  ),
]);

@widgetbook.UseCase(name: 'New records', type: RecordList)
Widget newRecords(BuildContext context) {
  final count = context.knobs.int.slider(
    label: 'Records',
    initialValue: 2,
    min: 1,
    max: 3,
  );
  const records = [
    RecordItem(
      name: 'Barbell Bench Press',
      detail: 'Heaviest weight · Best e1RM',
      value: '82.5 kg × 6',
      gain: '+2.5 kg',
    ),
    RecordItem(
      name: 'Barbell Row',
      detail: 'Most reps',
      value: '70 kg × 10',
      gain: '+2 reps',
    ),
    RecordItem(
      name: 'Plank',
      detail: 'Longest time',
      value: '75 s',
      gain: '+5 s',
    ),
  ];
  return _page([RecordList(records: records.take(count).toList())]);
}

@widgetbook.UseCase(name: 'No records · first workout', type: RecordList)
Widget firstRecords(BuildContext context) => _page([const RecordList.none()]);

@widgetbook.UseCase(name: 'No records · not beaten', type: RecordList)
Widget noRecords(BuildContext context) => _page([
  const RecordList.none(closest: 'Bench Press was 2.5 kg off your best.'),
]);

@widgetbook.UseCase(name: 'No records · one sentence', type: RecordList)
Widget recordMessage(BuildContext context) => _page([
  RecordList.message(
    message: context.knobs.string(
      label: 'Message',
      initialValue:
          'No new records this time. Bench Press was 2.5 kg off your best.',
    ),
  ),
]);
