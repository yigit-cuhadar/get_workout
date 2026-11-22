import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/widgets/set_table.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _page(List<Widget> children) => ListView(
  padding: const EdgeInsets.all(Gap.md),
  children: [Column(spacing: Gap.sm, children: children)],
);

@widgetbook.UseCase(name: 'Sets', type: SetTable)
Widget setsSetTable(BuildContext context) {
  final rir = context.knobs.boolean(label: 'RIR mode', initialValue: true);
  return _page([
    SetTable(
      name: 'Bench Press',
      rows: [
        const SetTableRow(label: 'W', values: '40 kg × 10'),
        SetTableRow(
          label: '1',
          values: '82.5 kg × 8',
          effort: rir ? 'RIR 2' : 'Moderate',
          record: true,
        ),
        SetTableRow(
          label: '2',
          values: '82.5 kg × 8',
          effort: rir ? 'RIR 1' : 'Hard',
        ),
        SetTableRow(
          label: '3',
          values: '82.5 kg × 7',
          effort: rir ? 'RIR 0' : 'Max',
        ),
        const SetTableRow(label: '4D', values: '82.5 kg × 6', effort: 'Failed'),
      ],
    ),
  ]);
}

@widgetbook.UseCase(name: 'Edit form', type: SetTable)
Widget editSetTable(BuildContext context) => const _EditForm();

@widgetbook.UseCase(name: 'Drops', type: SetTable)
Widget dropsSetTable(BuildContext context) => _page(const [
  SetTable(
    name: 'Bench Press',
    rows: [
      SetTableRow(label: '1', values: '82.5 kg × 8', effort: 'RIR 2'),
      SetTableRow(label: '2', values: '82.5 kg × 8', effort: 'RIR 1'),
      SetTableRow(label: '3', values: '82.5 kg × 7', effort: 'RIR 0'),
      SetTableRow(
        label: '4D',
        values: '82.5 kg × 6',
        effort: 'Failed',
        drops: ['60 kg × 8', '40 kg × 10'],
      ),
    ],
  ),
]);

@widgetbook.UseCase(name: 'By logging type', type: SetTable)
Widget loggingTypesSetTable(BuildContext context) => _page(const [
  SetTable(
    name: 'Plank',
    type: 'Duration',
    rows: [
      SetTableRow(label: '1', values: '45 s', effort: 'Moderate'),
      SetTableRow(label: '2', values: '50 s', effort: 'Hard'),
    ],
  ),
  SetTable(
    name: 'Push-up',
    type: 'Reps only',
    rows: [
      SetTableRow(label: '1', values: '15 reps', effort: 'Moderate'),
      SetTableRow(label: '2', values: '12 reps', effort: 'Max'),
    ],
  ),
  SetTable(
    name: "Farmer's Carry",
    type: 'Weight and time',
    rows: [SetTableRow(label: '1', values: '32 kg × 40 s', effort: 'Hard')],
  ),
  SetTable(
    name: 'Pull-up',
    type: 'Weighted bodyweight',
    rows: [SetTableRow(label: '1', values: '+10 kg × 6', effort: 'Hard')],
  ),
  SetTable(
    name: 'Dip',
    type: 'Assisted bodyweight',
    rows: [
      SetTableRow(label: '1', values: '20 kg assist × 8', effort: 'Moderate'),
    ],
  ),
]);

@widgetbook.UseCase(name: 'Notes', type: SetTable)
Widget notesSetTable(BuildContext context) => _page(const [
  SetTable(
    name: 'Back Squat',
    note: 'Belt on the top sets',
    rows: [
      SetTableRow(
        label: '1',
        values: '100 kg × 5',
        effort: 'Hard',
        note: 'Paused at the bottom',
      ),
      SetTableRow(label: '2', values: '100 kg × 5', effort: 'Max'),
    ],
  ),
]);

@widgetbook.UseCase(name: 'Group letters', type: SetTable)
Widget groupSetTable(BuildContext context) => _page(const [
  SetTable(
    name: 'Lateral Raise',
    group: 'A1',
    rows: [
      SetTableRow(label: '1', values: '10 kg × 15', effort: 'Moderate'),
      SetTableRow(label: '2', values: '10 kg × 14', effort: 'Hard'),
    ],
  ),
  SetTable(
    name: 'Triceps Pushdown',
    group: 'A2',
    rows: [
      SetTableRow(label: '1', values: '25 kg × 12', effort: 'Moderate'),
      SetTableRow(label: '2', values: '25 kg × 12', effort: 'Hard'),
    ],
  ),
]);

class _EditForm extends StatefulWidget {
  const _EditForm();

  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<_EditForm> {
  final _sets = [
    ('W', '40', '10', null),
    ('1', '82.5', '8', 'Moderate'),
    ('2', '82.5', '', null),
  ];
  final _done = [true, true, false];
  late final _controllers = [
    for (final (_, weight, reps, _) in _sets)
      (TextEditingController(text: weight), TextEditingController(text: reps)),
  ];

  @override
  void dispose() {
    for (final (weight, reps) in _controllers) {
      weight.dispose();
      reps.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _page([
    SetTable.edit(
      name: 'Bench Press',
      rows: [
        for (final (i, (label, _, _, effort)) in _sets.indexed)
          SetTableEditRow(
            label: label,
            semanticLabel: 'Set $label',
            done: _done[i],
            onToggle: () => setState(() => _done[i] = !_done[i]),
            onOptions: (_) {},
            effort: effort,
            onEffort: effort == null ? null : () {},
            inputs: [
              SetTableInput(
                label: 'Weight',
                controller: _controllers[i].$1,
                onChanged: (_) {},
                wide: true,
              ),
              SetTableInput(
                label: 'Reps',
                controller: _controllers[i].$2,
                onChanged: (_) {},
              ),
            ],
          ),
      ],
      menu: [
        ForgeMenuItem(
          label: 'Swap exercise',
          icon: ForgeIcons.sync,
          onTap: () {},
        ),
        ForgeMenuItem(
          label: 'Remove exercise',
          icon: ForgeIcons.delete,
          onTap: () {},
          destructive: true,
        ),
      ],
      onAddSet: () {},
    ),
  ]);
}

@widgetbook.UseCase(name: 'Opens and closes', type: SetTable)
Widget openingSetTable(BuildContext context) {
  final open = context.knobs.boolean(label: 'Open', initialValue: true);
  return _page([
    SetTable(
      name: 'Bench Press',
      count: '2 sets',
      open: open,
      onToggle: () {},
      rows: const [
        SetTableRow(label: 'W', values: '40 kg × 10'),
        SetTableRow(label: '1', values: '82.5 kg × 8', effort: 'Moderate'),
      ],
    ),
    SetTable(
      name: 'Incline Dumbbell Press',
      count: '3 sets',
      open: false,
      onToggle: () {},
      rows: const [SetTableRow(label: '1', values: '30 kg × 10')],
    ),
  ]);
}
