import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/widgets/set_bubble.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _bubble(
  BuildContext context, {
  required String label,
  bool done = false,
  bool selected = false,
  bool warmup = false,
}) => Center(
  child: SetBubble(
    label: context.knobs.string(label: 'Label', initialValue: label),
    semanticLabel: label,
    done: done,
    selected: selected,
    warmup: warmup,
    onTap: () {},
    onLongPress: () {},
  ),
);

@widgetbook.UseCase(name: 'Pending', type: SetBubble)
Widget setBubblePending(BuildContext context) => _bubble(context, label: '3');

@widgetbook.UseCase(name: 'Current', type: SetBubble)
Widget setBubbleCurrent(BuildContext context) =>
    _bubble(context, label: '2', selected: true);

@widgetbook.UseCase(name: 'Done', type: SetBubble)
Widget setBubbleDone(BuildContext context) =>
    _bubble(context, label: '1', done: true);

@widgetbook.UseCase(name: 'Done, selected', type: SetBubble)
Widget setBubbleDoneSelected(BuildContext context) =>
    _bubble(context, label: '1', done: true, selected: true);

@widgetbook.UseCase(name: 'Warm-up', type: SetBubble)
Widget setBubbleWarmup(BuildContext context) =>
    _bubble(context, label: 'W', warmup: true);

@widgetbook.UseCase(name: 'Warm-up, current', type: SetBubble)
Widget setBubbleWarmupCurrent(BuildContext context) =>
    _bubble(context, label: 'W', warmup: true, selected: true);

@widgetbook.UseCase(name: 'Warm-up, done', type: SetBubble)
Widget setBubbleWarmupDone(BuildContext context) =>
    _bubble(context, label: 'W', warmup: true, done: true);

@widgetbook.UseCase(name: 'Warm-up, done, selected', type: SetBubble)
Widget setBubbleWarmupDoneSelected(BuildContext context) =>
    _bubble(context, label: 'W', warmup: true, done: true, selected: true);

@widgetbook.UseCase(name: 'Drop', type: SetBubble)
Widget setBubbleDrop(BuildContext context) => _bubble(context, label: '3D');

@widgetbook.UseCase(name: 'Drop, current', type: SetBubble)
Widget setBubbleDropCurrent(BuildContext context) =>
    _bubble(context, label: '3D', selected: true);

@widgetbook.UseCase(name: 'Drop, done', type: SetBubble)
Widget setBubbleDropDone(BuildContext context) =>
    _bubble(context, label: '2D', done: true);

@widgetbook.UseCase(name: 'Drop, done, selected', type: SetBubble)
Widget setBubbleDropDoneSelected(BuildContext context) =>
    _bubble(context, label: '2D', done: true, selected: true);

@widgetbook.UseCase(name: 'Add set', type: SetBubble)
Widget setBubbleAdd(BuildContext context) => Center(
  child: SetBubble.add(semanticLabel: 'Add set', onTap: () {}),
);

/// Every form side by side, as the card shows them.
@widgetbook.UseCase(name: 'Every state', type: SetBubble)
Widget setBubbleAll(BuildContext context) => Padding(
  padding: const EdgeInsets.all(Gap.md),
  child: Wrap(
    spacing: Gap.md,
    runSpacing: Gap.md,
    children: [
      for (final (label, done, selected, warmup) in const [
        ('W', false, false, true),
        ('W', false, true, true),
        ('W', true, false, true),
        ('1', true, false, false),
        ('2', false, true, false),
        ('3', false, false, false),
        ('3D', false, false, false),
        ('2D', true, false, false),
        ('1', true, true, false),
      ])
        SetBubble(
          label: label,
          semanticLabel: label,
          done: done,
          selected: selected,
          warmup: warmup,
          onTap: () {},
        ),
      SetBubble.add(semanticLabel: 'Add set', onTap: () {}),
    ],
  ),
);
