import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../core/widgets/tap_band.dart';
import 'effort_question.dart';

/// One value of a set in a [SetPanel], shown as a [StepperField].
class SetPanelValue {
  const SetPanelValue({
    required this.value,
    required this.unit,
    required this.step,
    required this.onChanged,
    this.hint,
    this.min,
    this.max,
    this.signed = false,
    this.invalid = false,
  });

  final double? value;
  final String unit;
  final double step;
  final ValueChanged<double?> onChanged;
  final double? hint;
  final double? min;
  final double? max;

  /// Marks a value above zero with "+", as for a load added to the body.
  final bool signed;

  /// Rings the field in danger; the panel's error says what to do.
  final bool invalid;
}

/// A drop of a drop set: its [label] ("Drop 1"), its values and removing
/// it.
class SetPanelDrop {
  const SetPanelDrop({
    required this.label,
    required this.values,
    required this.onRemove,
  });

  final String label;
  final List<SetPanelValue> values;
  final VoidCallback onRemove;
}

/// The texts of a [SetPanel] that are the same for every set.
class SetPanelLabels {
  const SetPanelLabels({
    required this.log,
    required this.done,
    required this.options,
    required this.addDrop,
    required this.removeDrop,
    required this.plates,
  });

  final String log;
  final String done;
  final String options;
  final String addDrop;
  final String removeDrop;

  /// The plate button's name for a screen reader.
  final String plates;
}

/// The set entry fixed at the bottom of the workout screen: which set it
/// is ([title]) with its [details] (the last time) under it and a ⋯ menu,
/// its [values] as pill steppers (one full width, or two), a drop set's
/// [drops] right under them with Add drop, a done set's [effort], and Log
/// set, or Done once the set is done. An [error] says under the values
/// what to do about the [SetPanelValue.invalid] ones. With [onPlates], a
/// plate button beside the first value (the weight) opens its plate
/// breakdown.
///
/// A set picked while a rest runs has the [rest]'s thin line on top.
///
/// [SetPanel.showing] is the same panel showing something else in place of
/// the entry: after Log set the effort question, then the rest countdown,
/// or Finish workout once every set is done.
class SetPanel extends StatelessWidget {
  const SetPanel({
    super.key,
    required String this.title,
    required List<String> this.details,
    this.description,
    required List<SetPanelValue> this.values,
    required SetPanelLabels this.labels,
    required VoidCallback this.onOptions,
    required VoidCallback this.onLog,
    this.error,
    this.done = false,
    this.drops,
    this.onAddDrop,
    this.effort,
    this.onPlates,
    this.rest,
  }) : child = null;

  const SetPanel.showing({super.key, required Widget this.child})
    : title = null,
      details = null,
      description = null,
      values = null,
      labels = null,
      onOptions = null,
      onLog = null,
      error = null,
      done = false,
      drops = null,
      onAddDrop = null,
      effort = null,
      onPlates = null,
      rest = null;

  final String? title;
  final List<String>? details;

  /// What a set of its kind is, e.g. a warm-up's line, over the [details].
  final String? description;
  final List<SetPanelValue>? values;
  final SetPanelLabels? labels;
  final VoidCallback? onOptions;

  /// Always on: a set lacking a value is refused with an [error].
  final VoidCallback? onLog;
  final String? error;
  final bool done;

  /// Null unless it is a drop set.
  final List<SetPanelDrop>? drops;

  /// Null when no more drops can be added.
  final VoidCallback? onAddDrop;
  final Widget? effort;

  /// Opens the plate breakdown under the button whose context it is given;
  /// null hides the button.
  final ValueChanged<BuildContext>? onPlates;

  /// The rest running while a set is picked during it, as a [RestLine] on
  /// top.
  final EffortRest? rest;

  /// [child] brings its own padding.
  final Widget? child;

  /// The entry's padding.
  static const padding = EdgeInsets.fromLTRB(Gap.md, 14, Gap.md, 20);

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final radius = Radius.circular(style.radii.lg);
    // The drops' remove icons take taps past the padding.
    return TapBandArea(
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.vertical(top: radius),
          border: Border.all(color: colors.line),
        ),
        padding: child == null ? padding : EdgeInsets.zero,
        child: child ?? _entry(context),
      ),
    );
  }

  Widget _entry(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final labels = this.labels!;
    final drops = this.drops;
    // What does not fit the panel's share of the page scrolls between the
    // values and Log set.
    final middle = [
      if (drops != null) ...[
        for (final drop in drops) _drop(context, drop),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ForgeButton(
            label: labels.addDrop,
            onPressed: onAddDrop,
            variant: ForgeButtonVariant.text,
            size: ForgeButtonSize.small,
            leadingIcon: ForgeIcons.add,
          ),
        ),
      ],
      ?effort,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (rest case final rest?) RestLine(rest),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (description case final description?)
                    Text(
                      description,
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.inkMuted,
                      ),
                    ),
                  for (final line in details!)
                    Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: style.data.copyWith(color: colors.inkMuted),
                    ),
                ],
              ),
            ),
            // Drawn at the title's height, so a set without details
            // leaves no gap under it; its band takes the 44px.
            TapBand(
              child: Semantics(
                button: true,
                label: labels.options,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOptions,
                  child: ForgeIcon(
                    ForgeIcons.moreHoriz,
                    size: 20,
                    color: colors.inkMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
        _values(context, values!),
        if (error case final error?) StepperFieldError(error),
        if (middle.isNotEmpty)
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: middle,
              ),
            ),
          ),
        ForgeButton(
          label: done ? labels.done : labels.log,
          onPressed: onLog,
          leadingIcon: ForgeIcons.check,
          variant: done
              ? ForgeButtonVariant.secondary
              : ForgeButtonVariant.primary,
          size: ForgeButtonSize.large,
        ),
      ],
    );
  }

  Widget _values(BuildContext context, List<SetPanelValue> values) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 10,
    children: [
      for (final (i, value) in values.indexed) ...[
        Expanded(child: _field(value, compact: false)),
        if (i == 0)
          if (onPlates case final onPlates?) _platesButton(context, onPlates),
      ],
    ],
  );

  /// Ink-muted, no fill, 44px square, centred on the 50px pill.
  Widget _platesButton(
    BuildContext context,
    ValueChanged<BuildContext> onPlates,
  ) => Padding(
    padding: const EdgeInsets.symmetric(
      vertical: (StepperField.height - ForgeTheme.tapMin) / 2,
    ),
    child: Semantics(
      button: true,
      label: labels!.plates,
      excludeSemantics: true,
      child: Builder(
        builder: (button) => InkResponse(
          onTap: () => onPlates(button),
          child: SizedBox.square(
            dimension: ForgeTheme.tapMin,
            child: Center(
              child: ForgeIcon(
                ForgeIcons.fitnessCenter,
                size: 20,
                color: ForgeStyle.of(context).colors.inkMuted,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _field(SetPanelValue value, {required bool compact}) => StepperField(
    value: value.value,
    unit: value.unit,
    step: value.step,
    onChanged: value.onChanged,
    hint: value.hint,
    min: value.min,
    max: value.max,
    signed: value.signed,
    invalid: value.invalid,
    compact: compact,
  );

  Widget _drop(BuildContext context, SetPanelDrop drop) {
    final colors = ForgeStyle.of(context).colors;
    return Row(
      spacing: Gap.sm,
      children: [
        SizedBox(
          width: 46,
          child: Text(
            drop.label,
            style: Theme.of(context).textTheme.labelMedium!
                .copyWith(fontWeight: FontWeight.w400, color: colors.inkMuted),
          ),
        ),
        for (final value in drop.values)
          Expanded(child: _field(value, compact: true)),
        // Drawn in a 30 × 32 box, the icon 9px in, so the row keeps the
        // compact fields' 40px; its band reaches past the panel's padding.
        TapBand(
          child: Semantics(
            button: true,
            label: labels!.removeDrop,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: drop.onRemove,
              child: Container(
                width: 30,
                height: 32,
                padding: const EdgeInsets.only(left: 9),
                alignment: AlignmentDirectional.centerStart,
                child: ForgeIcon(
                  ForgeIcons.close,
                  size: 18,
                  color: colors.inkMuted,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
