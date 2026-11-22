import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/widgets/effort_question.dart';
import 'package:get_workout/features/workout/presentation/widgets/set_panel.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

const _labels = SetPanelLabels(
  log: 'Log set',
  done: 'Done',
  next: 'Next',
  options: 'Set options',
  addDrop: 'Add drop',
  removeDrop: 'Remove drop',
  plates: 'Plates',
);

SetPanelValue _value(
  double? value,
  String unit, {
  double step = 1,
  double? hint,
  bool signed = false,
  bool invalid = false,
}) => SetPanelValue(
  value: value,
  unit: unit,
  step: step,
  min: 0,
  hint: hint,
  signed: signed,
  invalid: invalid,
  onChanged: (_) {},
);

SetPanelValue _kg(
  double? kg, {
  String unit = 'kg',
  bool signed = false,
  bool invalid = false,
}) => _value(kg, unit, step: 2.5, signed: signed, invalid: invalid);

Widget _panel(
  String title,
  String last,
  List<SetPanelValue> values, {
  List<SetPanelDrop>? drops,
  bool done = false,
  String? error,
  Widget? effort,
  EffortRest? rest,
}) => Align(
  alignment: Alignment.bottomCenter,
  child: SetPanel(
    title: title,
    details: [last],
    values: values,
    labels: _labels,
    error: error,
    drops: drops,
    onAddDrop: drops == null ? null : () {},
    done: done,
    effort: effort,
    rest: rest,
    onOptions: () {},
    onLog: () {},
  ),
);

@widgetbook.UseCase(name: 'Entering the next set', type: SetPanel)
Widget setPanel(BuildContext context) => _panel(
  context.knobs.string(
    label: 'Title',
    initialValue: 'Bench Press · set 3 of 4',
  ),
  'Last time: 80 kg × 8',
  [
    _kg(context.knobs.double.input(label: 'Weight', initialValue: 82.5)),
    _value(8, 'reps'),
  ],
);

@widgetbook.UseCase(name: 'Warm-up', type: SetPanel)
Widget setPanelWarmup(BuildContext context) => Align(
  alignment: Alignment.bottomCenter,
  child: SetPanel(
    title: 'Bench Press · Warm-up 1 of 2',
    description: 'A lighter set to get ready. Not counted in your stats.',
    details: const [],
    values: [_kg(40), _value(8, 'reps')],
    labels: _labels,
    onOptions: () {},
    onLog: () {},
  ),
);

@widgetbook.UseCase(name: 'Missing value', type: SetPanel)
Widget setPanelMissing(BuildContext context) => _panel(
  'Bench Press · set 3 of 4',
  'Last time: 80 kg × 8',
  [_kg(null, invalid: true), _value(8, 'reps')],
  error: "Enter the set's values first.",
);

@widgetbook.UseCase(name: 'Reps only', type: SetPanel)
Widget setPanelReps(BuildContext context) =>
    _panel('Push-up · set 1 of 2', 'Last time: 15 reps', [_value(15, 'reps')]);

@widgetbook.UseCase(name: 'Duration', type: SetPanel)
Widget setPanelDuration(BuildContext context) =>
    _panel('Plank · set 2 of 3', 'Last time: 45 s', [_value(45, 's', step: 5)]);

@widgetbook.UseCase(name: 'Weighted bodyweight', type: SetPanel)
Widget setPanelWeighted(BuildContext context) => _panel(
  'Pull-up · set 2 of 3',
  'Last time: +10 kg × 6',
  [_kg(10, unit: 'kg added', signed: true), _value(6, 'reps')],
);

@widgetbook.UseCase(name: 'Assisted bodyweight', type: SetPanel)
Widget setPanelAssisted(BuildContext context) => _panel(
  'Dip · set 1 of 3',
  'Last time: 20 kg assist × 8',
  [_kg(20, unit: 'kg assist'), _value(8, 'reps')],
);

@widgetbook.UseCase(name: 'Weight and duration', type: SetPanel)
Widget setPanelWeightDuration(BuildContext context) => _panel(
  "Farmer's Carry · set 1 of 3",
  'Last time: 32 kg × 40 s',
  [_kg(32), _value(40, 's', step: 5)],
);

@widgetbook.UseCase(name: 'Drop set', type: SetPanel)
Widget setPanelDrop(BuildContext context) => _panel(
  'Bench Press · Drop set 4 of 4',
  'Last time: 80 kg × 6 · 60 × 8 · 40 × 10',
  [_kg(82.5), _value(6, 'reps')],
  drops: [
    for (final (i, (kg, reps)) in const [(60.0, 8.0), (40.0, 10.0)].indexed)
      SetPanelDrop(
        label: 'Drop ${i + 1}',
        values: [_kg(kg), _value(reps, 'reps')],
        onRemove: () {},
      ),
  ],
);

@widgetbook.UseCase(name: 'Selected done set', type: SetPanel)
Widget setPanelDone(BuildContext context) => _panel(
  'Bench Press · set 1 of 4',
  'Last time: 80 kg × 8',
  [_kg(82.5), _value(8, 'reps')],
  done: true,
  effort: const Text('Effort (built by EffortQuestion)'),
);

@widgetbook.UseCase(name: 'Set picked during a rest', type: SetPanel)
Widget setPanelResting(BuildContext context) => _panel(
  'Bench Press · set 4 of 4',
  'Last time: 80 kg × 7',
  [_kg(82.5), _value(8, 'reps')],
  rest: EffortRest(
    time: '1:12',
    progress: context.knobs.double.slider(
      label: 'Rest passed',
      initialValue: 0.4,
      max: 1,
    ),
    onAddTime: () {},
    onSkip: () {},
  ),
);

@widgetbook.UseCase(name: 'Every set done', type: SetPanel)
Widget setPanelFinish(BuildContext context) => Align(
  alignment: Alignment.bottomCenter,
  child: SetPanel.showing(
    child: Padding(
      padding: SetPanel.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Text('All sets done', style: Theme.of(context).textTheme.titleMedium),
          ForgeButton(
            label: 'Finish workout',
            onPressed: () {},
            size: ForgeButtonSize.large,
          ),
        ],
      ),
    ),
  ),
);

@widgetbook.UseCase(name: 'Showing the effort or the rest', type: SetPanel)
Widget setPanelShowing(BuildContext context) => const Align(
  alignment: Alignment.bottomCenter,
  child: SetPanel.showing(child: Text('EffortQuestion or RestPanel')),
);

@widgetbook.UseCase(name: 'Plate breakdown', type: SetPanel)
Widget setPanelPlates(BuildContext context) => Align(
  alignment: Alignment.bottomCenter,
  child: SetPanel(
    title: 'Bench Press · set 3 of 4',
    details: const ['Last time: 80 kg × 8'],
    values: [_kg(82.5), _value(8, 'reps')],
    labels: _labels,
    onPlates: (button) => showForgeInfo(
      context: button,
      title: '82.5 kg',
      facts: const [('Bar', '20 kg'), ('Each side', '25 + 5 + 1.25 kg')],
    ),
    onOptions: () {},
    onLog: () {},
  ),
);
