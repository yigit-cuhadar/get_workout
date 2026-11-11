import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/exercise.dart';
import '../domain/muscle_meshes.dart';
import 'body_model_cubit.dart';
import 'exercise_catalogue_cubit.dart';
import 'exercise_detail_cubit.dart';
import 'vocabulary_labels.dart';
import 'widgets/exercise_tile.dart';

class ExerciseDetailPage extends StatelessWidget {
  const ExerciseDetailPage({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<ExerciseDetailCubit>(param1: exerciseId),
    child: const _DetailView(),
  );
}

class _DetailView extends StatelessWidget {
  const _DetailView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<ExerciseDetailCubit, ExerciseDetailState>(
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: state is DetailReady
              ? Text(state.exercise.localized(context).name)
              : null,
          actions: [
            if (state is DetailReady) FavoriteButton(state.exercise.id),
          ],
        ),
        body: switch (state) {
          DetailLoading() => const LoadingView(),
          DetailFailed() => ErrorView(
            message: l10n.libraryLoadFailed,
            retryLabel: l10n.retry,
            onRetry: context.read<ExerciseCatalogueCubit>().retry,
          ),
          DetailNotFound() => EmptyView(message: l10n.detailNotFound),
          DetailReady() => _DetailBody(state),
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody(this.detail);

  final DetailReady detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercise = detail.exercise;
    final text = exercise.localized(context);
    final colors = _MuscleColors.of(context);
    return ListView(
      children: [
        if (text.aliases.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Text(l10n.detailAliases(text.aliases.join(', '))),
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
        _Fact(l10n.detailLevel, l10n.levelName(exercise.level)),
        _Fact(l10n.detailMechanic, l10n.mechanicName(exercise.mechanic)),
        _Fact(
          l10n.detailMovementPattern,
          l10n.movementPatternName(exercise.movementPattern),
        ),
        _Fact(l10n.detailLaterality, l10n.lateralityName(exercise.laterality)),
        _Fact(
          l10n.detailLoggingType,
          l10n.loggingTypeName(exercise.loggingType),
        ),
        ..._steps(l10n.detailSetup, text.setup, numbered: true),
        ..._steps(l10n.detailExecution, text.execution, numbered: true),
        ..._steps(l10n.detailMistakes, text.mistakes),
        if (text.safety case final safety?)
          ..._steps(l10n.detailSafety, [safety]),
        ..._steps(l10n.detailCues, text.cues),
        ..._exercises(l10n.detailAlternatives, detail.alternatives),
        ..._exercises(l10n.detailVariations, detail.variations),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  static List<Widget> _steps(
    String title,
    List<String> lines, {
    bool numbered = false,
  }) => [
    if (lines.isNotEmpty) ...[
      _Header(title),
      for (final (index, line) in lines.indexed)
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
          child: Text(
            numbered
                ? '${index + 1}. $line'
                : lines.length > 1
                ? '• $line'
                : line,
          ),
        ),
    ],
  ];

  static List<Widget> _exercises(String title, List<Exercise> exercises) => [
    if (exercises.isNotEmpty) ...[
      _Header(title),
      for (final exercise in exercises) ExerciseTile(exercise),
    ],
  ];
}

/// The model, not interactive, with the worked muscles coloured and a
/// front/back switch.
class _MusclePreview extends StatefulWidget {
  const _MusclePreview(this.exercise);

  final Exercise exercise;

  @override
  State<_MusclePreview> createState() => _MusclePreviewState();
}

enum _Side { front, back }

class _MusclePreviewState extends State<_MusclePreview> {
  final _camera = ModelViewerController();
  var _side = _Side.front;

  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _turn(_Side side) {
    setState(() => _side = side);
    _camera.animateTo(side == _Side.front ? 0 : math.pi, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = _MuscleColors.of(context);
    final exercise = widget.exercise;
    final state = context.watch<BodyModelCubit>().state;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: switch (state) {
            BodyModelLoading() => const LoadingView(),
            BodyModelFailed() => Center(child: Text(l10n.modelLoadFailed)),
            BodyModelReady(:final model) => ModelViewer(
              model: model,
              controller: _camera,
              interactive: false,
              partColors: {
                for (final muscle in exercise.secondaryMuscles)
                  for (final mesh in muscle.meshNames) mesh: colors.secondary,
                for (final muscle in exercise.mainMuscles)
                  for (final mesh in muscle.meshNames) mesh: colors.main,
              },
              semanticLabel: l10n.detailModelLabel(
                l10n.muscleNames([
                  ...exercise.mainMuscles,
                  ...exercise.secondaryMuscles,
                ]),
              ),
            ),
          },
        ),
        SegmentedButton<_Side>(
          segments: [
            ButtonSegment(value: _Side.front, label: Text(l10n.detailFront)),
            ButtonSegment(value: _Side.back, label: Text(l10n.detailBack)),
          ],
          selected: {_side},
          onSelectionChanged: (selection) => _turn(selection.single),
        ),
      ],
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
