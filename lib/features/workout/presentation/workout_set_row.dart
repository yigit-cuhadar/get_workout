import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/max_length_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/set_logging.dart';
import '../domain/workout.dart';
import 'active_workout_cubit.dart';
import 'workout_text.dart';

/// The column widths of a set row, shared with its heading.
abstract final class SetColumns {
  static const label = 2;
  static const previous = 3;
  static const value = 2;
}

/// The headings above an exercise's sets.
class SetHeading extends StatelessWidget {
  const SetHeading({super.key, required this.type, required this.unit});

  final LoggingType type;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.labelSmall;
    Widget cell(int flex, String text) => Expanded(
      flex: flex,
      child: Text(text, style: style, textAlign: TextAlign.center),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
      child: Row(
        children: [
          cell(SetColumns.label, l10n.workoutSetColumn),
          cell(SetColumns.previous, l10n.workoutPreviousColumn),
          if (type.logsWeight)
            cell(SetColumns.value, l10n.weightColumn(type, unit)),
          cell(
            SetColumns.value,
            type.isDurationBased
                ? l10n.workoutSecondsColumn
                : l10n.workoutRepsColumn,
          ),
          // Under the tick button.
          const Opacity(opacity: 0, child: Icon(Icons.check_circle)),
          const SizedBox(width: Gap.sm),
        ],
      ),
    );
  }
}

/// One set: its kind (tap for its options), last time's set at the same
/// place, its values with the suggestion as hint, and the tick. Drops of a
/// drop set follow it.
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.ref,
    required this.state,
    required this.unit,
    required this.effort,
  });

  final SetRef ref;
  final ActiveWorkoutState state;
  final WeightUnit unit;
  final EffortScale effort;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    final exercise = state.workout!.exercises[ref.exercise];
    final set = exercise.sets[ref.set];
    final type = exercise.loggingType;
    final previous = state.lastTime(ref);
    final hint = state.suggestion(ref);
    final number = exercise.sets
        .take(ref.set + 1)
        .where((s) => !s.isWarmup)
        .length;
    final flags = [
      if (set.toFailure) l10n.workoutFailureShort,
      if (set.rir case final rir?)
        l10n.effortText(rir, rpe: effort == EffortScale.rpe),
      ?set.note,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
          child: Row(
            children: [
              Expanded(
                flex: SetColumns.label,
                child: TextButton(
                  onPressed: () => _openOptions(context),
                  child: Text(switch (set.type) {
                    SetType.warmup => l10n.workoutWarmupShort,
                    SetType.drop => '$number${l10n.workoutDropShort}',
                    SetType.normal => '$number',
                  }, semanticsLabel: l10n.workoutSetActions(ref.set + 1)),
                ),
              ),
              Expanded(
                flex: SetColumns.previous,
                child: Text(
                  previous == null ? '–' : l10n.setText(previous, type, unit),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (type.logsWeight)
                Expanded(
                  flex: SetColumns.value,
                  child: NumberCell(
                    value: set.weightKg == null
                        ? null
                        : unit.fromKg(set.weightKg!),
                    hint: hint.weightKg == null
                        ? null
                        : l10n.weightField(hint.weightKg!, unit),
                    decimal: true,
                    onChanged: (text) => cubit.setWeight(ref, text, unit),
                  ),
                ),
              Expanded(
                flex: SetColumns.value,
                child: type.isDurationBased
                    ? NumberCell(
                        value: set.durationS?.toDouble(),
                        hint: hint.durationS?.toString(),
                        onChanged: (text) => cubit.setDuration(ref, text),
                      )
                    : NumberCell(
                        value: set.reps?.toDouble(),
                        hint: hint.reps?.toString(),
                        onChanged: (text) => cubit.setReps(ref, text),
                      ),
              ),
              IconButton(
                tooltip: set.done ? l10n.workoutUntick : l10n.workoutTick,
                isSelected: set.done,
                color: set.done ? theme.colorScheme.primary : null,
                icon: const Icon(Icons.check_circle_outline),
                selectedIcon: const Icon(Icons.check_circle),
                onPressed: () => cubit.toggleDone(
                  ref,
                  restTimer: context
                      .read<SettingsCubit>()
                      .state
                      .settings
                      .restTimer,
                ),
              ),
            ],
          ),
        ),
        if (flags.isNotEmpty)
          _Indented(
            child: Text(flags.join(' · '), style: theme.textTheme.bodySmall),
          ),
        if (state.invalidSet == ref)
          _Indented(
            child: Text(
              l10n.workoutSetInvalid,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        for (final (d, drop) in set.drops.indexed)
          _DropRow(ref: ref, index: d, drop: drop, type: type, unit: unit),
        if (set.type == SetType.drop &&
            set.drops.length < WorkoutLimits.maxDrops)
          _Indented(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(l10n.workoutAddDrop),
                onPressed: () => cubit.addDrop(ref),
              ),
            ),
          ),
      ],
    );
  }

  void _openOptions(BuildContext context) {
    final cubit = context.read<ActiveWorkoutCubit>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: _SetOptions(ref: ref, effort: effort),
      ),
    );
  }
}

class _Indented extends StatelessWidget {
  const _Indented({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: Gap.xl, right: Gap.md),
    child: child,
  );
}

class _DropRow extends StatelessWidget {
  const _DropRow({
    required this.ref,
    required this.index,
    required this.drop,
    required this.type,
    required this.unit,
  });

  final SetRef ref;
  final int index;
  final Drop drop;
  final LoggingType type;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
      child: Row(
        children: [
          const Spacer(flex: SetColumns.label),
          Expanded(
            flex: SetColumns.previous,
            child: Text(
              l10n.workoutDrop(index + 1),
              textAlign: TextAlign.center,
            ),
          ),
          if (type.logsWeight)
            Expanded(
              flex: SetColumns.value,
              child: NumberCell(
                value: drop.weightKg == null
                    ? null
                    : unit.fromKg(drop.weightKg!),
                decimal: true,
                onChanged: (text) =>
                    cubit.setDropWeight(ref, index, text, unit),
              ),
            ),
          Expanded(
            flex: SetColumns.value,
            child: NumberCell(
              value: drop.reps?.toDouble(),
              onChanged: (text) => cubit.setDropReps(ref, index, text),
            ),
          ),
          IconButton(
            tooltip: l10n.workoutRemoveDrop,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => cubit.removeDrop(ref, index),
          ),
        ],
      ),
    );
  }
}

/// A number field showing [value] (in display units). It keeps what the
/// user types while that still means [value], and shows [value] when it
/// changes from elsewhere, e.g. a tick filling in the suggestion.
class NumberCell extends StatefulWidget {
  const NumberCell({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.decimal = false,
  });

  final double? value;
  final String? hint;
  final bool decimal;
  final ValueChanged<String> onChanged;

  @override
  State<NumberCell> createState() => _NumberCellState();
}

class _NumberCellState extends State<NumberCell> {
  late final _controller = TextEditingController(text: _format(widget.value));

  String _format(double? value) => value == null
      ? ''
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  @override
  void didUpdateWidget(NumberCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shown = _parse(_controller.text);
    final value = widget.value;
    final same = shown == null || value == null
        ? shown == value
        : (shown - value).abs() < 1e-6;
    if (!same) _controller.text = _format(value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
    child: TextField(
      controller: _controller,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
      inputFormatters: [
        widget.decimal
            ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            : FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(widget.decimal ? 7 : 5),
      ],
      decoration: InputDecoration(isDense: true, hintText: widget.hint),
      onChanged: widget.onChanged,
    ),
  );
}

/// A set's kind, failure flag, effort and removal; every change applies at
/// once.
class _SetOptions extends StatelessWidget {
  const _SetOptions({required this.ref, required this.effort});

  final SetRef ref;
  final EffortScale effort;

  /// Reps in reserve offered; 5 stands for "5 or more".
  static const _rirChoices = [0, 1, 2, 3, 4, 5];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<ActiveWorkoutCubit>();
    return BlocBuilder<ActiveWorkoutCubit, ActiveWorkoutState>(
      builder: (context, state) {
        final exercise = state.workout?.exercises.elementAtOrNull(ref.exercise);
        final set = exercise?.sets.elementAtOrNull(ref.set);
        if (exercise == null || set == null) return const SizedBox.shrink();
        final rpe = effort == EffortScale.rpe;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: Gap.md,
              right: Gap.md,
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: Gap.sm,
                  children: [
                    for (final type in SetType.values)
                      if (type != SetType.drop || exercise.loggingType.logsReps)
                        ChoiceChip(
                          label: Text(l10n.setTypeLabel(type)),
                          selected: set.type == type,
                          onSelected: (_) => cubit.setType(ref, type),
                        ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.workoutToFailure),
                  value: set.toFailure,
                  onChanged: (value) => cubit.setToFailure(ref, value),
                ),
                if (effort != EffortScale.off) ...[
                  Text(
                    rpe
                        ? l10n.workoutEffortRpeQuestion
                        : l10n.workoutEffortRirQuestion,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: Gap.sm),
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.xs,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.workoutEffortNone),
                        selected: set.rir == null,
                        onSelected: (_) => cubit.setRir(ref, null),
                      ),
                      for (final rir in _rirChoices)
                        ChoiceChip(
                          label: Text(
                            rpe
                                ? '${10 - rir}'
                                : rir == _rirChoices.last
                                ? l10n.workoutRirFivePlus
                                : '$rir',
                          ),
                          selected: set.rir == rir,
                          onSelected: (_) => cubit.setRir(ref, rir),
                        ),
                    ],
                  ),
                ],
                TextFormField(
                  initialValue: set.note,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [
                    maxLengthFormatter(WorkoutLimits.maxSetNoteLength),
                  ],
                  decoration: InputDecoration(labelText: l10n.workoutSetNote),
                  onChanged: (text) => cubit.setSetNote(ref, text),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(l10n.workoutRemoveSet),
                  onTap: () {
                    Navigator.pop(context);
                    cubit.removeSet(ref);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
