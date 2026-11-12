import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/workout.dart';
import 'keep_visible.dart';
import 'workout_editor.dart';
import 'workout_editor_view.dart';
import 'workout_text.dart';

/// [SetView.bubbles]: the sets of exercises [start] to [end] (one, or a
/// superset or circuit) as bubbles. One exercise wraps its bubbles; a group
/// stacks a row per exercise, led by its [groupItemLabel], the warm-ups
/// first, then each round in a column, a round's bubbles joined.
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
    const empty = SizedBox.square(dimension: kMinInteractiveDimension);
    Widget row(int k) => Row(
      spacing: Gap.sm,
      children: [
        SizedBox.square(
          dimension: kMinInteractiveDimension,
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
              : empty,
        for (final set in working[k]) _setBubble(start + k, set),
        _AddBubble(exercise: start + k, editor: editor, state: state),
      ],
    );
    // Joins the bubbles of a round in rows [k] and [k + 1].
    Widget connectors(int k) => Row(
      spacing: Gap.sm,
      children: [
        for (var slot = 0; slot <= warmupSlots; slot++)
          const SizedBox(width: kMinInteractiveDimension),
        for (var round = 0; round < working[k].length; round++)
          SizedBox(
            width: kMinInteractiveDimension,
            height: Gap.sm,
            child: round < working[k + 1].length
                ? const VerticalDivider(width: kMinInteractiveDimension)
                : null,
          ),
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
    final bubble = _Bubble(
      label: l10n.setBubbleLabel(exercise, ref.set),
      selected: selected,
      done: set.done,
      dashed: set.isWarmup,
      onTap: () => editor.selectSet(ref),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.setLabel(exercise, ref.set), style: style),
          if (set.done) Icon(Icons.check, size: style?.fontSize),
        ],
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

/// A round button of the size of a tap target, outlined, dashed or filled
/// as selected or done.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.label,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.done = false,
    this.dashed = false,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final bool selected;
  final bool done;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final outline = selected ? colors.primary : colors.outline;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: kMinInteractiveDimension,
        child: CustomPaint(
          foregroundPainter: dashed ? _DashedCircle(outline) : null,
          child: Material(
            color: selected
                ? colors.primaryContainer
                : done
                ? colors.secondaryContainer
                : colors.surface,
            shape: CircleBorder(
              side: dashed ? BorderSide.none : BorderSide(color: outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed outline of a warm-up's bubble.
class _DashedCircle extends CustomPainter {
  const _DashedCircle(this.color);

  final Color color;

  static const _dashes = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    final rect = Offset.zero & size;
    const sweep = math.pi / _dashes;
    for (var i = 0; i < _dashes; i++) {
      canvas.drawArc(rect.deflate(0.5), i * 2 * sweep, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle oldDelegate) => oldDelegate.color != color;
}
