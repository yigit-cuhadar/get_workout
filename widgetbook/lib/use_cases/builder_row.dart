import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/programs/presentation/widgets/builder_row.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

typedef _Item = ({String name, List<(String, String)> values});

final _menu = [
  ForgeMenuItem(
    label: 'Edit sets and reps',
    icon: ForgeIcons.tune,
    onTap: () {},
  ),
  ForgeMenuItem(
    label: 'Remove',
    icon: ForgeIcons.delete,
    onTap: () {},
    destructive: true,
  ),
];

/// The day's rows in their card; [group] the indexes of a superset or
/// circuit, whose first carries [header]; [lifted] the one being dragged.
Widget _day(
  List<_Item> items, {
  Set<int> group = const {},
  String? header,
  int? lifted,
}) => CustomScrollView(
  slivers: [
    SliverPadding(
      padding: const EdgeInsets.all(Gap.md),
      sliver: BuilderCard(
        sliver: SliverReorderableList(
          itemCount: items.length,
          onReorderItem: (_, _) {},
          itemBuilder: (context, i) {
            final grouped = group.contains(i);
            final first = grouped && !group.contains(i - 1);
            return BuilderRow(
              key: ValueKey(i),
              index: i,
              name: items[i].name,
              values: [
                for (final (label, value) in items[i].values)
                  BuilderValue(label: label, value: value, onTap: () {}),
              ],
              menu: _menu,
              divided: i > 0 && (!grouped || first),
              grouped: grouped,
              groupHeader: first ? header : null,
              lifted: i == lifted,
            );
          },
        ),
      ),
    ),
  ],
);

@widgetbook.UseCase(name: 'Day with a superset', type: BuilderRow)
Widget dayBuilderRow(BuildContext context) => _day(
  [
    (
      name: 'Bench Press',
      values: [('Sets', '4'), ('Reps', '6–8'), ('Rest', '2:00')],
    ),
    (
      name: 'Incline Dumbbell Press',
      values: [('Sets', '3'), ('Reps', '8–10'), ('Rest', '1:30')],
    ),
    (
      name: 'Overhead Press',
      values: [('Sets', '3'), ('Reps', '6–8'), ('Rest', '2:00')],
    ),
    (name: 'Lateral Raise', values: [('Sets', '3'), ('Reps', '12–15')]),
    (
      name: 'Triceps Pushdown',
      values: [('Sets', '3'), ('Reps', '10–12'), ('Rest', '1:30')],
    ),
    (
      name: 'Push-up',
      values: [('Sets', '2'), ('Reps', '10–15'), ('Rest', '1:00')],
    ),
  ],
  group: {3, 4},
  header: 'Superset · rest after both 1:30',
  lifted: context.knobs.boolean(label: 'Dragging', initialValue: true)
      ? 1
      : null,
);

@widgetbook.UseCase(name: 'Circuit', type: BuilderRow)
Widget circuitBuilderRow(BuildContext context) => _day(
  [
    (
      name: 'Back Squat',
      values: [('Sets', '4'), ('Reps', '6–8'), ('Rest', '3:00')],
    ),
    (name: 'Leg Press', values: [('Reps', '10–12')]),
    (name: 'Leg Curl', values: [('Reps', '10–12')]),
    (name: 'Plank', values: [('Time', '45 s')]),
  ],
  group: {1, 2, 3},
  header: 'Circuit · 3 rounds · rest after each round 1:30',
);

@widgetbook.UseCase(name: 'Timed item', type: BuilderRow)
Widget timedBuilderRow(BuildContext context) => _day([
  (name: 'Plank', values: [('Sets', '3'), ('Time', '45 s'), ('Rest', '1:00')]),
  (
    name: 'Dead Hang',
    values: [('Sets', '2'), ('Time', '30 s'), ('Rest', '1:30')],
  ),
]);

@widgetbook.UseCase(name: 'Unavailable exercise', type: BuilderRow)
Widget unavailableBuilderRow(BuildContext context) => CustomScrollView(
  slivers: [
    SliverPadding(
      padding: const EdgeInsets.all(Gap.md),
      sliver: BuilderCard(
        sliver: SliverReorderableList(
          itemCount: 2,
          onReorderItem: (_, _) {},
          itemBuilder: (context, i) => i == 0
              ? BuilderRow(
                  key: const ValueKey(0),
                  index: 0,
                  name: 'Bench Press',
                  values: [
                    for (final (label, value) in [
                      ('Sets', '4'),
                      ('Reps', '6–8'),
                      ('Rest', '2:00'),
                    ])
                      BuilderValue(label: label, value: value, onTap: () {}),
                  ],
                  menu: _menu,
                  divided: false,
                )
              : BuilderRow.unavailable(
                  key: const ValueKey(1),
                  index: 1,
                  name: 'Unavailable exercise',
                  help: 'No longer in the library. Replace or remove it.',
                  menu: [
                    ForgeMenuItem(
                      label: 'Replace exercise',
                      icon: ForgeIcons.sync,
                      onTap: () {},
                    ),
                    ForgeMenuItem(
                      label: 'Remove',
                      icon: ForgeIcons.delete,
                      onTap: () {},
                      destructive: true,
                    ),
                  ],
                ),
        ),
      ),
    ),
  ],
);
