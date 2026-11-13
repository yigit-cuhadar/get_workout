import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../programs/presentation/add_to_program.dart';
import '../../programs/presentation/add_to_program_cubit.dart';
import '../../workout/presentation/start_workout.dart';
import '../domain/exercise.dart';
import '../domain/muscle_meshes.dart';
import 'body_model_cubit.dart';
import 'exercise_catalogue_cubit.dart';
import 'exercise_detail_cubit.dart';
import 'vocabulary_labels.dart';
import 'widgets/exercise_tile.dart';

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

enum _CustomAction { edit, delete }

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
              FavoriteButton(state.exercise.id),
              _AddButton(state.exercise),
              if (state.exercise.isCustom)
                PopupMenuButton<_CustomAction>(
                  onSelected: (action) => switch (action) {
                    _CustomAction.edit => context.push(
                      Routes.customExerciseEdit(state.exercise.id),
                    ),
                    _CustomAction.delete => _delete(context),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _CustomAction.edit,
                      child: Text(l10n.customEdit),
                    ),
                    PopupMenuItem(
                      value: _CustomAction.delete,
                      enabled: !state.deleting,
                      child: Text(l10n.customDelete),
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

/// The one Add action: to the workout in progress (or a new one), or to a
/// program.
class _AddButton extends StatelessWidget {
  const _AddButton(this.exercise);

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: () => addToWorkout(context, exercise),
          child: Text(l10n.addToWorkout),
        ),
        MenuItemButton(
          onPressed: () => _addToProgram(context),
          child: Text(l10n.addToProgram),
        ),
      ],
      builder: (_, menu, _) => Tooltip(
        message: l10n.detailActions,
        child: TextButton.icon(
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          icon: const Icon(Icons.add),
          label: Text(l10n.detailAdd),
        ),
      ),
    );
  }

  Future<void> _addToProgram(BuildContext context) async {
    final cubit = sl<AddToProgramCubit>();
    await addToProgram(context, exercise, cubit);
    await cubit.close();
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
    final colors = _MuscleColors.of(context);
    // A custom exercise has none of these but the logging type and equipment.
    final facts = [
      if (exercise.equipment.isNotEmpty)
        (
          l10n.detailEquipment,
          [
            l10n.equipmentNames(exercise.equipment),
            for (final set in exercise.equipmentAlternatives)
              l10n.detailEquipmentOr(l10n.equipmentNames(set)),
          ].join('\n'),
        ),
      if (exercise.level case final level?)
        (l10n.detailLevel, l10n.levelName(level)),
      if (exercise.mechanic case final mechanic?)
        (l10n.detailMechanic, l10n.mechanicName(mechanic)),
      if (exercise.movementPattern case final pattern?)
        (l10n.detailMovementPattern, l10n.movementPatternName(pattern)),
      if (exercise.laterality case final laterality?)
        (l10n.detailLaterality, l10n.lateralityName(laterality)),
      (l10n.detailLoggingType, l10n.loggingTypeName(exercise.loggingType)),
      if (text.aliases.isNotEmpty)
        (l10n.detailAliases, l10n.inlineList(text.aliases)),
    ];
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
        _MusclePreview(exercise),
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
        _Section(child: _Facts(facts)),
        if (text.setup.isNotEmpty)
          _Section(title: l10n.detailSetup, child: _NumberedSteps(text.setup)),
        if (text.execution.isNotEmpty)
          _Section(
            title: l10n.detailExecution,
            child: _NumberedSteps(text.execution),
          ),
        if (text.mistakes.isNotEmpty)
          _Section(
            title: l10n.detailMistakes,
            icon: Icons.close,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final mistake in text.mistakes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.xs),
                    child: Text(l10n.stepBullet(mistake)),
                  ),
              ],
            ),
          ),
        if (text.safety case final safety?)
          _Section(
            title: l10n.detailSafety,
            icon: Icons.warning_amber_outlined,
            child: Text(safety),
          ),
        if (text.cues.isNotEmpty)
          _Section(
            title: l10n.detailCues,
            child: Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [for (final cue in text.cues) Chip(label: Text(cue))],
            ),
          ),
        if (exercise.note case final note? when note.isNotEmpty)
          _Section(title: l10n.detailNote, child: Text(note)),
        if (detail.alternatives.isNotEmpty || detail.variations.isNotEmpty) ...[
          _Header(l10n.detailSimilar),
          for (final other in detail.alternatives)
            ExerciseTile(
              other,
              route: exerciseRoute,
              tag: l10n.detailAlternative,
            ),
          for (final other in detail.variations)
            ExerciseTile(
              other,
              route: exerciseRoute,
              tag: l10n.detailVariation,
            ),
        ],
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}

/// A card of its own on the page, under an optional [title] with an [icon].
class _Section extends StatelessWidget {
  const _Section({required this.child, this.title, this.icon});

  final String? title;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final icon = this.icon;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Semantics(
                  header: true,
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon),
                        const SizedBox(width: Gap.sm),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.sm),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Label and value rows, the labels in one column.
class _Facts extends StatelessWidget {
  const _Facts(this.facts);

  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodyMedium;
    final valueStyle = Theme.of(context).textTheme.titleSmall;
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth()},
      children: [
        for (final (label, value) in facts)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: Gap.md,
                  bottom: Gap.sm,
                ),
                child: Text(label, style: labelStyle),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Text(value, style: valueStyle),
              ),
            ],
          ),
      ],
    );
  }
}

/// Steps numbered from 1.
class _NumberedSteps extends StatelessWidget {
  const _NumberedSteps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (index, step) in steps.indexed)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(child: Text('${index + 1}')),
          title: Text(step),
        ),
    ],
  );
}

/// The model from the front and from the back side by side, with the worked
/// muscles coloured. Neither view takes gestures, so the page scrolls over
/// them.
class _MusclePreview extends StatefulWidget {
  const _MusclePreview(this.exercise);

  final Exercise exercise;

  @override
  State<_MusclePreview> createState() => _MusclePreviewState();
}

class _MusclePreviewState extends State<_MusclePreview> {
  /// Share of the screen height the model takes, leaving the muscles and the
  /// first facts in view below it.
  static const _heightRatio = 1 / 3;

  // A viewer without a controller faces the front.
  final _back = ModelViewerController(yaw: math.pi);

  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = _MuscleColors.of(context);
    final exercise = widget.exercise;
    final state = context.watch<BodyModelCubit>().state;
    final partColors = {
      for (final muscle in exercise.secondaryMuscles)
        for (final mesh in muscle.meshNames) mesh: colors.secondary,
      for (final muscle in exercise.mainMuscles)
        for (final mesh in muscle.meshNames) mesh: colors.main,
    };
    Widget side(String label, Model3D model, {ModelViewerController? camera}) =>
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: ModelViewer(
                  model: model,
                  controller: camera,
                  interactive: false,
                  partColors: partColors,
                ),
              ),
              Text(label),
            ],
          ),
        );
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * _heightRatio,
      child: switch (state) {
        BodyModelLoading() => const LoadingView(),
        BodyModelFailed() => Center(child: Text(l10n.modelLoadFailed)),
        BodyModelReady(:final model) => Semantics(
          label: l10n.detailModelLabel(
            l10n.muscleNames([
              ...exercise.mainMuscles,
              ...exercise.secondaryMuscles,
            ]),
          ),
          image: true,
          excludeSemantics: true,
          child: Row(
            children: [
              side(l10n.detailFront, model),
              side(l10n.detailBack, model, camera: _back),
            ],
          ),
        ),
      },
    );
  }
}

/// Main muscles in the primary colour, secondary ones in a lighter tone of it.
class _MuscleColors {
  const _MuscleColors(this.main, this.secondary);

  factory _MuscleColors.of(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final hsl = HSLColor.fromColor(primary);
    return _MuscleColors(
      primary,
      hsl.withLightness(hsl.lightness + (1 - hsl.lightness) * 0.55).toColor(),
    );
  }

  final Color main;
  final Color secondary;
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
