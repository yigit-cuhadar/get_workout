import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/records.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _page(List<Widget> children) => SingleChildScrollView(
  padding: const EdgeInsets.all(Gap.md),
  child: Column(spacing: 10, children: children),
);

@widgetbook.UseCase(name: 'Biggest record and the rest', type: RecordHighlight)
Widget biggestRecord(BuildContext context) => _page([
  RecordHighlight(
    value: context.knobs.string(label: 'Value', initialValue: '82.5 kg × 8'),
    line: 'Bench Press · e1RM 104 kg · +2.5 kg',
  ),
  const RecordList(
    records: [
      RecordItem(
        name: 'Overhead Press',
        detail: 'Best weight for 8 reps',
        value: '50 kg × 8',
        gain: '+2.5 kg',
      ),
    ],
  ),
]);

@widgetbook.UseCase(name: 'No records · first workout', type: RecordList)
Widget firstRecords(BuildContext context) => _page([const RecordList.none()]);

@widgetbook.UseCase(name: 'No records · not beaten', type: RecordList)
Widget noRecords(BuildContext context) => _page([
  const RecordList.none(closest: 'Bench Press was 2.5 kg off your best.'),
]);
