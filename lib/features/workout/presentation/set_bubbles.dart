import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/set_logging.dart';
import '../domain/workout.dart';
import 'keep_visible.dart';
import 'workout_editor.dart';
import 'workout_editor_view.dart';
import 'workout_text.dart';

/// The sets of exercises [start] to [end] (one, or a superset or circuit)
/// as bubbles. One exercise wraps its bubbles; a group stacks a row per
/// exercise, led by its [groupItemLabel], the warm-ups first, then each
/// round in a column, a round's bubbles joined. Tapping a bubble selects
/// its set; long-pressing it offers the other set types and removal.
class SetBubbles extends StatelessWidget {
  const SetBubbles({
    super.key,
    required this.start,
    required this.end,
    required this.state,
    required this.editor,
  });

  final int start;
  final int end;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final exercises = state.workout!.exercises;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
      child: end - start == 1
          ? Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                for (final (s, _) in exercises[start].sets.indexed)
                  _setBubble(start, s),
                _AddBubble(exercise: start, editor: editor, state: state),
              ],
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _grid(context, exercises),
            ),
    );
  }

  Widget _setBubble(int exercise, int set) => _SetBubble(
    ref: (exercise: exercise, set: set),
    state: state,
    editor: editor,
  );

  Widget _grid(BuildContext context, List<WorkoutExercise> exercises) {
    final group = [for (var i = start; i < end; i++) exercises[i]];
    final warmups = [
      for (final e in group)
        [
          for (final (j, s) in e.sets.indexed)
            if (s.isWarmup) j,
        ],
    ];
    final working = [
      for (final e in group)
        [
          for (final (j, s) in e.sets.indexed)
            if (!s.isWarmup) j,
        ],
    ];
    final warmupSlots = warmups.map((w) => w.length).fold(0, math.max);
    final rounds = working.map((w) => w.length).fold(0, math.max);
    final size = bubbleSize(context);
    // Whether a row in [from, to) has a set in [round].
    bool any(int from, int to, int round) =>
        working.sublist(from, to).any((w) => round < w.length);
    Widget empty([double? height]) =>
        SizedBox(width: size, height: height ?? size);
    Widget line([double? height]) => SizedBox(
      width: size,
      height: height ?? size,
      child: VerticalDivider(width: size),
    );
    Widget row(int k) => Row(
      spacing: Gap.sm,
      children: [
        SizedBox.square(
          dimension: size,
          child: Center(
            child: Text(
              groupItemLabel(exercises, start + k),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
        for (var slot = 0; slot < warmupSlots; slot++)
          slot < warmups[k].length
              ? _setBubble(start + k, warmups[k][slot])
              : empty(),
        for (var round = 0; round < rounds; round++)
          round < working[k].length
              ? _setBubble(start + k, working[k][round])
              // A round's line passes a row without a set in it.
              : any(0, k, round) && any(k + 1, group.length, round)
              ? line()
              : empty(),
        _AddBubble(exercise: start + k, editor: editor, state: state),
      ],
    );
    // Joins the bubbles of a round across the gap below row [k].
    Widget connectors(int k) => Row(
      spacing: Gap.sm,
      children: [
        for (var slot = 0; slot <= warmupSlots; slot++) empty(Gap.sm),
        for (var round = 0; round < rounds; round++)
          any(0, k + 1, round) && any(k + 1, group.length, round)
              ? line(Gap.sm)
              : empty(Gap.sm),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var k = 0; k < group.length; k++) ...[
          if (k > 0) connectors(k - 1),
          row(k),
        ],
      ],
    );
  }
}

class _SetBubble extends StatelessWidget {
  const _SetBubble({
    required this.ref,
    required this.state,
    required this.editor,
  });

  final SetRef ref;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final exercise = state.workout!.exercises[ref.exercise];
    final set = exercise.sets[ref.set];
    final selection = state.selection;
    final selected =
        selection?.exercise == ref.exercise && selection?.set == ref.set;
    final style = theme.textTheme.labelLarge;
    // The same as the set bar's options: see WorkoutEditor.setType.
    final actions = {
      for (final type in exercise.loggingType.setTypes)
        if (type != set.type)
          l10n.workoutChangeSetType(l10n.setTypeLabel(type)): () =>
              editor.setType(ref, type),
      l10n.workoutRemoveSet: () => editor.removeSet(ref),
    };
    final bubble = MenuAnchor(
      menuChildren: [
        for (final MapEntry(key: label, value: action) in actions.entries)
          MenuItemButton(onPressed: action, child: Text(label)),
      ],
      builder: (context, menu, _) => _Bubble(
        label: l10n.setBubbleLabel(exercise, ref.set),
        selected: selected,
        done: set.done,
        dashed: set.isWarmup,
        onTap: () => editor.selectSet(ref),
        onLongPress: menu.open,
        actions: {
          for (final MapEntry(key: label, value: action) in actions.entries)
            CustomSemanticsAction(label: label): action,
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.setLabel(exercise, ref.set), style: style),
            if (set.done) Icon(Icons.check, size: style?.fontSize),
          ],
        ),
      ),
    );
    return selected ? KeepVisible(child: bubble) : bubble;
  }
}

class _AddBubble extends StatelessWidget {
  const _AddBubble({
    required this.exercise,
    required this.state,
    required this.editor,
  });

  final int exercise;
  final EditedWorkout state;
  final WorkoutEditor<EditedWorkout> editor;

  @override
  Widget build(BuildContext context) {
    final full =
        state.workout!.exercises[exercise].sets.length >= WorkoutLimits.maxSets;
    return _Bubble(
      label: AppLocalizations.of(context).workoutAddSet,
      onTap: full ? null : () => addSetOfKind(context, editor, exercise),
      child: const Icon(Icons.add),
    );
  }
}

/// A bubble's side: a tap target, grown with the text scale so its label
/// and tick fit.
double bubbleSize(BuildContext context) => math.max(
  kMinInteractiveDimension,
  MediaQuery.textScalerOf(context).scale(kMinInteractiveDimension),
);

/// A round button of [bubbleSize], outlined, dashed or filled as selected
/// or done. [actions], also offered by [onLongPress], reach screen readers
/// as custom actions.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.label,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.actions,
    this.selected = false,
    this.done = false,
    this.dashed = false,
  });

  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Map<CustomSemanticsAction, VoidCallback>? actions;
  final Widget child;
  final bool selected;
  final bool done;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final side = BorderSide(color: selected ? colors.primary : colors.outline);
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      customSemanticsActions: actions,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: bubbleSize(context),
        child: CustomPaint(
          foregroundPainter: dashed ? _DashedCircle(side) : null,
          child: Material(
            color: selected
                ? colors.primaryContainer
                : done
                ? colors.secondaryContainer
                : colors.surface,
            shape: CircleBorder(side: dashed ? BorderSide.none : side),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed outline of a warm-up's bubble, drawn as [side] would be.
class _DashedCircle extends CustomPainter {
  const _DashedCircle(this.side);

  final BorderSide side;

  static const _dashes = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = side.toPaint();
    final rect = (Offset.zero & size).deflate(side.width / 2);
    const sweep = math.pi / _dashes;
    for (var i = 0; i < _dashes; i++) {
      canvas.drawArc(rect, i * 2 * sweep, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle oldDelegate) => oldDelegate.side != side;
}
