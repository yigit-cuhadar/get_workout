import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/widgets/exercise_card.dart';
import 'package:get_workout/features/workout/presentation/widgets/set_bubble.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _page(List<Widget> cards) => ListView(
  padding: const EdgeInsets.all(Gap.md),
  children: [
    for (final card in cards)
      Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: card,
      ),
  ],
);

ExerciseCardItem _item(
  String name,
  int done,
  int total, {
  String? letter,
  List<String> details = const [],
  ExerciseCardSets? sets,
}) => ExerciseCardItem(
  name: name,
  count: '$done/$total',
  progress: done / total,
  allDone: done == total,
  letter: letter,
  details: details,
  sets: sets,
  onTap: () {},
  onOptions: (_) {},
);

SetBubble _bubble(String label, {bool done = false, bool current = false}) =>
    SetBubble(
      label: label,
      semanticLabel: label,
      done: done,
      selected: current,
      warmup: label == 'W',
      onTap: () {},
    );

Widget _add() => SetBubble.add(semanticLabel: 'Add set', onTap: () {});

ExerciseCard _card(
  List<ExerciseCardItem> items, {
  ExerciseCardForm form = ExerciseCardForm.collapsed,
  String? group,
}) => ExerciseCard(
  items: items,
  form: form,
  group: group,
  optionsLabel: 'Exercise options',
);

@widgetbook.UseCase(name: 'Collapsed', type: ExerciseCard)
Widget exerciseCardCollapsed(BuildContext context) {
  final done = context.knobs.int.slider(
    label: 'Sets done',
    initialValue: 1,
    min: 0,
    max: 3,
  );
  return _page([
    _card([_item('Bench Press', 5, 5)]),
    _card([_item('Incline Dumbbell Press', done, 3)]),
    _card([_item('Overhead Press', 0, 3)]),
    _card(group: 'Superset A', [
      _item('Lateral Raise', 0, 3, letter: 'A1'),
      _item('Triceps Pushdown', 0, 3, letter: 'A2'),
    ]),
  ]);
}

@widgetbook.UseCase(name: 'Open', type: ExerciseCard)
Widget exerciseCardOpen(BuildContext context) => _page([
  _card(form: ExerciseCardForm.open, [
    _item(
      context.knobs.string(label: 'Name', initialValue: 'Bench Press'),
      3,
      5,
      details: const [
        'Goal: 4 × 6–8 · 82.5 kg',
        'Last time: Fri, Nov 6 · 80 kg × 8',
        'Use the flat bench',
      ],
      sets: ExerciseCardSets(
        warmups: [_bubble('W', done: true)],
        working: [
          _bubble('1', done: true),
          _bubble('2', done: true),
          _bubble('3', current: true),
          _bubble('4'),
        ],
        add: _add(),
      ),
    ),
  ]),
  _card([_item('Incline Dumbbell Press', 0, 3)]),
]);

@widgetbook.UseCase(name: 'Circuit', type: ExerciseCard)
Widget exerciseCardCircuit(BuildContext context) => _page([
  _card(group: 'Circuit B', [
    _item('Leg Press', 2, 3, letter: 'B1'),
    _item('Leg Curl', 1, 3, letter: 'B2'),
    _item('Plank', 1, 3, letter: 'B3'),
  ]),
]);

@widgetbook.UseCase(name: 'Open superset or circuit', type: ExerciseCard)
Widget exerciseCardOpenGroup(BuildContext context) => _page([
  _card(
    form: ExerciseCardForm.open,
    group: 'Circuit B · rest after each round 1:30',
    [
      for (final (i, (name, goal)) in const [
        ('Leg Press', 'Goal: 3 × 10–12 · 140 kg'),
        ('Leg Curl', 'Goal: 3 × 10–12 · 40 kg'),
        ('Plank', 'Goal: 3 × 45 s'),
      ].indexed)
        _item(
          name,
          i == 0 ? 2 : 1,
          3,
          letter: 'B${i + 1}',
          details: [goal],
          sets: ExerciseCardSets(
            warmups: const [],
            working: [
              _bubble('1', done: true),
              _bubble('2', done: i == 0, current: i == 1),
              _bubble('3'),
            ],
            add: _add(),
          ),
        ),
    ],
  ),
]);

@widgetbook.UseCase(name: 'Reorder', type: ExerciseCard)
Widget exerciseCardReorder(BuildContext context) => _page([
  _card(form: ExerciseCardForm.line, [_item('Incline Dumbbell Press', 0, 3)]),
  _card(form: ExerciseCardForm.lifted, [_item('Bench Press', 3, 5)]),
  _card(form: ExerciseCardForm.line, [_item('Overhead Press', 0, 3)]),
  _card(form: ExerciseCardForm.line, group: 'Superset A', [
    _item('Lateral Raise', 0, 3, letter: 'A1'),
    _item('Triceps Pushdown', 0, 3, letter: 'A2'),
  ]),
]);
