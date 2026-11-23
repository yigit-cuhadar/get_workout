import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/workout.dart';
import 'widgets/set_table.dart';
import 'workout_text.dart';

/// An exercise as logged, as a [SetTable]: its [group] letter, name (the
/// catalogue's, else the one stored with it), logging type (when not
/// weight and reps), note and set count over a row per set, the sets at
/// [records] tagged, each drop on its own row under its set. With
/// [onToggle] it opens and closes.
class ExerciseSetTable extends StatelessWidget {
  const ExerciseSetTable({
    super.key,
    required this.exercise,
    required this.group,
    this.records = const {},
    this.open = true,
    this.onToggle,
  });

  final WorkoutExercise exercise;
  final String? group;

  /// The indexes of the sets holding a record.
  final Set<int> records;
  final bool open;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final unit = settings.weightUnit;
    final type = exercise.loggingType;
    final catalogue = context.watch<ExerciseCatalogueCubit>().state;
    final known = catalogue is CatalogueReady
        ? catalogue.exercises
              .where((e) => e.id == exercise.exerciseId)
              .firstOrNull
        : null;
    return SetTable(
      name: known?.localized(context).name ?? exercise.name,
      group: group,
      type: type == LoggingType.weightReps ? null : l10n.loggingTypeName(type),
      note: exercise.note,
      count: l10n.historySetCount(exercise.sets.length),
      open: open,
      onToggle: onToggle,
      rows: [
        for (final (i, set) in exercise.sets.indexed)
          SetTableRow(
            label: l10n.setLabel(exercise, i),
            values: l10n.setWithUnitText(set, type, unit),
            effort: l10n.effortText(set, settings.effortScale),
            record: records.contains(i),
            note: set.note,
            drops: [
              for (final drop in set.drops)
                l10n.setWithUnitText(
                  WorkoutSet(weightKg: drop.weightKg, reps: drop.reps),
                  type,
                  unit,
                ),
            ],
          ),
      ],
    );
  }
}
