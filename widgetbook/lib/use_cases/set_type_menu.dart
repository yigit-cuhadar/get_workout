import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/workout/presentation/widgets/set_type_menu.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

Widget _menu({required bool drop}) => Padding(
  padding: const EdgeInsets.all(Gap.md),
  child: Align(
    alignment: Alignment.topLeft,
    child: SetTypeMenu(
      types: [
        SetTypeMenuItem(
          label: 'Warm-up',
          bubble: 'W',
          warmup: true,
          onTap: () {},
        ),
        SetTypeMenuItem(
          label: 'Working',
          bubble: '3',
          current: true,
          onTap: () {},
        ),
        if (drop)
          SetTypeMenuItem(label: 'Drop set', bubble: '3D', onTap: () {}),
      ],
      removeLabel: 'Remove set',
      onRemove: () {},
    ),
  ),
);

@widgetbook.UseCase(name: 'Long-press a set bubble', type: SetTypeMenu)
Widget setTypeMenu(BuildContext context) => _menu(drop: true);

@widgetbook.UseCase(name: 'Non-rep exercise (no drop set)', type: SetTypeMenu)
Widget setTypeMenuNoDrop(BuildContext context) => _menu(drop: false);

@widgetbook.UseCase(name: 'Set options sheet', type: SetTypeList)
Widget setTypeList(BuildContext context) => Padding(
  padding: const EdgeInsets.all(Gap.md),
  child: Material(
    color: ForgeStyle.of(context).colors.surface,
    child: SetTypeList(
      types: [
        SetTypeMenuItem(
          label: 'Warm-up',
          bubble: 'W',
          warmup: true,
          onTap: () {},
        ),
        SetTypeMenuItem(
          label: 'Working',
          bubble: '3',
          current: true,
          onTap: () {},
        ),
        SetTypeMenuItem(label: 'Drop set', bubble: '3D', onTap: () {}),
      ],
    ),
  ),
);

@widgetbook.UseCase(name: 'Add set', type: AddSetSheet)
Widget addSetSheet(BuildContext context) {
  final tip = context.knobs.boolean(
    label: 'First time (tip)',
    initialValue: true,
  );
  final drop = context.knobs.boolean(label: 'Rep exercise', initialValue: true);
  return Align(
    alignment: Alignment.bottomCenter,
    child: Material(
      color: ForgeStyle.of(context).colors.surface,
      child: AddSetSheet(
        title: 'Add set',
        tip: tip
            ? TipBanner(
                message:
                    'Warm-ups never count toward records or volume. A drop '
                    'set keeps going at a lower weight.',
                dismissLabel: 'Got it',
                onDismiss: () {},
              )
            : null,
        options: [
          AddSetOption(
            label: 'Normal',
            hint: 'A working set at the end',
            bubble: '5',
            onTap: () {},
          ),
          AddSetOption(
            label: 'Warm-up',
            hint: 'Goes after the other warm-ups',
            bubble: 'W',
            warmup: true,
            onTap: () {},
          ),
          if (drop)
            AddSetOption(
              label: 'Drop set',
              hint: 'Lower the weight and keep going',
              bubble: '5D',
              onTap: () {},
            ),
        ],
      ),
    ),
  );
}
