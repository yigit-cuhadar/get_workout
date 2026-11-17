import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/grouping.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../workout/presentation/workout_text.dart';
import '../domain/program.dart';
import '../domain/program_editing.dart';
import 'program_text.dart';

/// One day of a program as a card of rows: its name over its exercise
/// count (and estimate, with [estimate]) and a chevron that points down
/// while closed and up while [open]; open, the day's exercises follow in
/// the same card ([rows] in place of [programDayRows] when given); with
/// [onStart], ▶ in front of the chevron starts the day.
/// Which days are open is the page's own view state.
class ProgramDayCard extends StatelessWidget {
  const ProgramDayCard({
    super.key,
    required this.day,
    required this.index,
    required this.open,
    required this.onToggle,
    this.estimate = true,
    this.onExerciseTap,
    this.onStart,
    this.rows,
  });

  final ProgramDay day;
  final int index;
  final bool open;
  final VoidCallback onToggle;
  final bool estimate;

  /// With it, an exercise of the library opens from its row.
  final ValueChanged<String>? onExerciseTap;
  final VoidCallback? onStart;
  final List<Widget>? rows;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    final count = day.items.length;
    return ListRowCard(
      children: [
        ListRow(
          title: l10n.dayTitle(index, day.name),
          detail: estimate
              ? l10n.programDaySummary(
                  count,
                  l10n.estimateText(estimateDay(day)),
                )
              : l10n.programExerciseCount(count),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onStart case final start?)
                Semantics(
                  button: true,
                  label: l10n.workoutStartThisDay,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: start,
                    child: SizedBox.square(
                      dimension: ForgeTheme.tapMin,
                      child: Center(
                        child: ForgeIcon(
                          ForgeIcons.playArrow,
                          size: 18,
                          color: style.colors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              Semantics(
                label: open ? l10n.programDayHide : l10n.programDayShow,
                child: ForgeIcon(
                  open ? ForgeIcons.expandLess : ForgeIcons.expandMore,
                  size: 18,
                  color: style.colors.inkMuted,
                ),
              ),
            ],
          ),
          onTap: onToggle,
        ),
        if (open)
          ...rows ?? programDayRows(context, day, onExerciseTap: onExerciseTap),
      ],
    );
  }
}

/// A program day's exercises as rows of a [ListRowCard]: each its name
/// over "4 × 6–8 · Rest 2:00"; a superset or circuit gets a muted row over
/// it, "Superset A · rest after each round 1:30", and its exercises lose
/// their own rest. With [onExerciseTap], an exercise of the library opens
/// from its row, which then ends in a chevron.
List<Widget> programDayRows(
  BuildContext context,
  ProgramDay day, {
  ValueChanged<String>? onExerciseTap,
}) {
  final l10n = AppLocalizations.of(context);
  final unit = context.select(
    (SettingsCubit cubit) => cubit.state.settings.weightUnit,
  );
  final catalogue = context.select(
    (ExerciseCatalogueCubit cubit) => cubit.state,
  );
  final exercises = catalogue is CatalogueReady
      ? {for (final e in catalogue.exercises) e.id: e}
      : null;
  final items = day.items;
  Widget row(ProgramItem item, {required bool grouped}) {
    final opens = onExerciseTap != null && exercises?[item.exerciseId] != null;
    return ListRow(
      title: _name(context, l10n, exercises, item),
      detail: grouped
          ? l10n.itemSummary(item, unit)
          : l10n.programItemLine(
              l10n.itemSummary(item, unit),
              l10n.elapsedText(Duration(seconds: item.restS)),
            ),
      end: opens ? ListRowEnd.chevron : ListRowEnd.none,
      onTap: opens ? () => onExerciseTap(item.exerciseId) : null,
    );
  }

  return [
    for (final (start, end) in groupBlocks(items))
      if (items[start].group case final group? when end - start > 1) ...[
        _GroupLabel(
          l10n.workoutGroupRest(
            l10n.groupLabel(group, end - start),
            l10n.elapsedText(Duration(seconds: items[end - 1].restS)),
          ),
        ),
        for (var i = start; i < end; i++) row(items[i], grouped: true),
      ] else
        row(items[start], grouped: false),
  ];
}

String _name(
  BuildContext context,
  AppLocalizations l10n,
  Map<String, Exercise>? exercises,
  ProgramItem item,
) {
  if (exercises == null) return l10n.programExerciseLoading;
  final exercise = exercises[item.exerciseId];
  return exercise == null
      ? l10n.programExerciseUnavailable
      : exercise.localized(context).name;
}

/// The muted line over a superset's or circuit's exercises.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium!.copyWith(
        fontWeight: FontWeight.w600,
        color: ForgeStyle.of(context).colors.inkMuted,
      ),
    ),
  );
}
