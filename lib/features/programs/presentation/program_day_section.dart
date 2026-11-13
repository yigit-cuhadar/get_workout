import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/grouping.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/program.dart';
import '../domain/program_editing.dart';
import 'program_text.dart';

/// One day of a program, read-only: its name and estimate, then its
/// exercises. With [onExerciseTap], an exercise of the library opens.
class ProgramDaySection extends StatelessWidget {
  const ProgramDaySection({
    super.key,
    required this.day,
    required this.index,
    this.onExerciseTap,
  });

  final ProgramDay day;
  final int index;
  final ValueChanged<String>? onExerciseTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        ListTile(
          title: Text(
            l10n.dayName(day, index),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: day.items.isEmpty
              ? null
              : Text(l10n.estimateText(estimateDay(day))),
        ),
        ProgramDayItems(day: day, onExerciseTap: onExerciseTap),
      ],
    );
  }
}

/// A program day's exercises, one row each, with sets, rest and group.
/// With [onExerciseTap], an exercise of the library opens.
class ProgramDayItems extends StatelessWidget {
  const ProgramDayItems({super.key, required this.day, this.onExerciseTap});

  final ProgramDay day;
  final ValueChanged<String>? onExerciseTap;

  @override
  Widget build(BuildContext context) {
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
    final onTap = onExerciseTap;
    bool opens(ProgramItem item) =>
        onTap != null && exercises?[item.exerciseId] != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in day.items.indexed)
          ListTile(
            dense: true,
            leading: item.group == null ? null : Text(item.group!),
            title: Text(_name(l10n, exercises, item, context)),
            subtitle: Text(
              [
                l10n.itemSummary(item, unit),
                l10n.programRest(item.restS),
                if (item.group case final group?)
                  l10n.groupLabel(group, groupSize(day.items, i)),
              ].join(' · '),
            ),
            trailing: opens(item) ? const Icon(Icons.chevron_right) : null,
            onTap: opens(item) ? () => onTap!(item.exerciseId) : null,
          ),
      ],
    );
  }

  static int groupSize(List<ProgramItem> items, int index) {
    final (start, end) = groupRange(items, index);
    return end - start;
  }

  static String _name(
    AppLocalizations l10n,
    Map<String, Exercise>? exercises,
    ProgramItem item,
    BuildContext context,
  ) {
    if (exercises == null) return l10n.programExerciseLoading;
    final exercise = exercises[item.exerciseId];
    return exercise == null
        ? l10n.programExerciseUnavailable
        : exercise.localized(context).name;
  }
}
