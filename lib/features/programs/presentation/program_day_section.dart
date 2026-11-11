import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/program.dart';
import '../domain/program_editing.dart';
import 'program_text.dart';

/// One day of a program, read-only: its name and estimate, [action] if
/// any, then its exercises. With [onExerciseTap], an exercise of the
/// library opens.
class ProgramDaySection extends StatelessWidget {
  const ProgramDaySection({
    super.key,
    required this.day,
    required this.index,
    this.onExerciseTap,
    this.action,
  });

  final ProgramDay day;
  final int index;
  final ValueChanged<String>? onExerciseTap;

  /// Something to do with this day, e.g. start it.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
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
        const Divider(),
        ListTile(
          title: Text(
            l10n.dayName(day, index),
            style: theme.textTheme.titleMedium,
          ),
          trailing: day.items.isEmpty
              ? null
              : Text(l10n.estimateText(estimateDay(day))),
        ),
        if (action case final action?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: action,
            ),
          ),
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
