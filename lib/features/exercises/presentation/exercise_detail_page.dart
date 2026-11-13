import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../programs/presentation/add_to_program.dart';
import '../../programs/presentation/add_to_program_cubit.dart';
import '../../workout/presentation/start_workout.dart';
import '../domain/exercise.dart';
import 'exercise_catalogue_cubit.dart';
import 'exercise_detail_cubit.dart';
import 'vocabulary_labels.dart';
import 'widgets/exercise_tile.dart';
import 'widgets/muscle_preview.dart';

class ExerciseDetailPage extends StatelessWidget {
  const ExerciseDetailPage({
    super.key,
    required this.exerciseId,
    required this.exerciseRoute,
  });

  final String exerciseId;

  /// Where another exercise opens, so it stays in the tab hosting this one.
  final String Function(String id) exerciseRoute;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<ExerciseDetailCubit>(param1: exerciseId),
    child: _DetailView(exerciseRoute),
  );
}

enum _DetailAction { workout, program }

class _DetailView extends StatelessWidget {
  const _DetailView(this.exerciseRoute);

  final String Function(String id) exerciseRoute;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<ExerciseDetailCubit, ExerciseDetailState>(
      listener: (context, state) {
        if (state is DetailDeleted) {
          context.pop();
        } else if (state case DetailReady(:final deleteFailure?)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                deleteFailure is NetworkFailure
                    ? l10n.errorNetwork
                    : l10n.customDeleteFailed,
              ),
            ),
          );
        }
      },
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: state is DetailReady
              ? Text(state.exercise.localized(context).name)
              : null,
          actions: [
            if (state is DetailReady) ...[
              if (state.exercise.isCustom) ...[
                IconButton(
                  tooltip: l10n.customEdit,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => context.push(
                    Routes.customExerciseEdit(state.exercise.id),
                  ),
                ),
                IconButton(
                  tooltip: l10n.customDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: state.deleting ? null : () => _delete(context),
                ),
              ],
              FavoriteButton(state.exercise.id),
              PopupMenuButton<_DetailAction>(
                tooltip: l10n.detailActions,
                onSelected: (action) => switch (action) {
                  _DetailAction.workout => addToWorkout(
                    context,
                    state.exercise,
                  ),
                  _DetailAction.program => _addToProgram(
                    context,
                    state.exercise,
                  ),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _DetailAction.workout,
                    child: Text(l10n.addToWorkout),
                  ),
                  PopupMenuItem(
                    value: _DetailAction.program,
                    child: Text(l10n.addToProgram),
                  ),
                ],
              ),
            ],
          ],
        ),
        body: switch (state) {
          DetailLoading() || DetailDeleted() => const LoadingView(),
          DetailFailed() => ErrorView(
            message: l10n.libraryLoadFailed,
            retryLabel: l10n.retry,
            onRetry: context.read<ExerciseCatalogueCubit>().retry,
          ),
          DetailNotFound() => EmptyView(message: l10n.detailNotFound),
          DetailReady() => _DetailBody(state, exerciseRoute),
        },
      ),
    );
  }

  static Future<void> _addToProgram(
    BuildContext context,
    Exercise exercise,
  ) async {
    final cubit = sl<AddToProgramCubit>();
    await addToProgram(context, exercise, cubit);
    await cubit.close();
  }

  static Future<void> _delete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ExerciseDetailCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.customDeleteTitle),
        content: Text(l10n.customDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.customDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) await cubit.delete();
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody(this.detail, this.exerciseRoute);

  final DetailReady detail;
  final String Function(String id) exerciseRoute;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercise = detail.exercise;
    final text = exercise.localized(context);
    final colors = MuscleColors.of(context);
    String numbered(int index, String line) =>
        l10n.stepNumbered(index + 1, line);
    String bulleted(int _, String line) => l10n.stepBullet(line);
    return ListView(
      children: [
        if (exercise.isCustom)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Chip(label: Text(l10n.customLabel)),
            ),
          ),
        if (text.aliases.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Text(l10n.detailAliases(l10n.inlineList(text.aliases))),
          ),
        // Leaves the muscles and the first facts in view below it.
        MusclePreview(
          main: exercise.mainMuscles,
          secondary: exercise.secondaryMuscles,
          heightRatio: 1 / 3,
        ),
        ListTile(
          leading: Icon(Icons.circle, color: colors.main),
          title: Text(l10n.detailMainMuscles),
          subtitle: Text(l10n.muscleNames(exercise.mainMuscles)),
        ),
        if (exercise.secondaryMuscles.isNotEmpty)
          ListTile(
            leading: Icon(Icons.circle, color: colors.secondary),
            title: Text(l10n.detailSecondaryMuscles),
            subtitle: Text(l10n.muscleNames(exercise.secondaryMuscles)),
          ),
        if (exercise.equipment.isNotEmpty)
          ListTile(
            title: Text(l10n.detailEquipment),
            subtitle: Text(
              [
                l10n.equipmentNames(exercise.equipment),
                for (final set in exercise.equipmentAlternatives)
                  l10n.detailEquipmentOr(l10n.equipmentNames(set)),
              ].join('\n'),
            ),
          ),
        // A custom exercise has none of these but the logging type.
        if (exercise.level case final level?)
          _Fact(l10n.detailLevel, l10n.levelName(level)),
        if (exercise.mechanic case final mechanic?)
          _Fact(l10n.detailMechanic, l10n.mechanicName(mechanic)),
        if (exercise.movementPattern case final pattern?)
          _Fact(l10n.detailMovementPattern, l10n.movementPatternName(pattern)),
        if (exercise.laterality case final laterality?)
          _Fact(l10n.detailLaterality, l10n.lateralityName(laterality)),
        _Fact(
          l10n.detailLoggingType,
          l10n.loggingTypeName(exercise.loggingType),
        ),
        ListTile(
          leading: const Icon(Icons.trending_up),
          title: Text(l10n.detailProgress),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              context.push(Routes.exerciseStrength(exerciseRoute(exercise.id))),
        ),
        if (exercise.note case final note?)
          ..._lines(l10n.detailNote, [note], (_, line) => line),
        ..._lines(l10n.detailSetup, text.setup, numbered),
        ..._lines(l10n.detailExecution, text.execution, numbered),
        ..._lines(l10n.detailMistakes, text.mistakes, bulleted),
        if (text.safety case final safety?)
          ..._lines(l10n.detailSafety, [safety], (_, line) => line),
        ..._lines(l10n.detailCues, text.cues, bulleted),
        ..._exercises(l10n.detailAlternatives, detail.alternatives),
        ..._exercises(l10n.detailVariations, detail.variations),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  /// A titled text section, each line written by [format].
  static List<Widget> _lines(
    String title,
    List<String> lines,
    String Function(int index, String line) format,
  ) => [
    if (lines.isNotEmpty) ...[
      _Header(title),
      for (final (index, line) in lines.indexed)
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
          child: Text(format(index, line)),
        ),
    ],
  ];

  List<Widget> _exercises(String title, List<Exercise> exercises) => [
    if (exercises.isNotEmpty) ...[
      _Header(title),
      for (final exercise in exercises)
        ExerciseTile(exercise, route: exerciseRoute),
    ],
  ];
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      ListTile(title: Text(label), subtitle: Text(value));
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: ListTile(
      title: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}
