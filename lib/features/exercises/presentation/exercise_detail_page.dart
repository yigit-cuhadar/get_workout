import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/muscle_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../analytics/domain/analytics.dart';
import '../../programs/presentation/add_to_program.dart';
import '../../programs/presentation/add_to_program_cubit.dart';
import '../../workout/presentation/start_workout.dart';
import '../domain/exercise.dart';
import 'body_model_cubit.dart';
import 'exercise_catalogue_cubit.dart';
import 'exercise_detail_cubit.dart';
import 'exercise_motion_cubit.dart';
import 'favorites_cubit.dart';
import 'vocabulary_labels.dart';
import 'widgets/exercise_motion_view.dart';
import 'widgets/exercise_tile.dart';

class ExerciseDetailPage extends StatelessWidget {
  const ExerciseDetailPage({
    super.key,
    required this.exerciseId,
    required this.exerciseRoute,
    required this.from,
  });

  final String exerciseId;

  /// Where the page was opened, for analytics.
  final ExerciseViewSource from;

  /// Where another exercise opens, so it stays in the tab hosting this one.
  final String Function(String id) exerciseRoute;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<ExerciseDetailCubit>(param1: exerciseId, param2: from),
    child: _DetailView(exerciseRoute),
  );
}

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
          showForgeSnackbar(
            context,
            message: deleteFailure is NetworkFailure
                ? l10n.errorNetwork
                : l10n.customDeleteFailed,
            error: true,
          );
        }
      },
      builder: (context, state) => Scaffold(
        appBar: ForgeAppBar(
          title: state is DetailReady
              ? state.exercise.localized(context).name
              : '',
          actions: [if (state is DetailReady) _MoreAction(state)],
        ),
        body: switch (state) {
          DetailLoading() || DetailDeleted() => const _Loading(),
          DetailFailed() => ListView(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
            children: [
              ErrorView(
                title: l10n.libraryLoadFailed,
                message: l10n.loadFailedDetail,
                retryLabel: l10n.retry,
                onRetry: context.read<ExerciseCatalogueCubit>().retry,
                card: true,
              ),
            ],
          ),
          DetailNotFound() => ListView(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
            children: [
              EmptyView(
                icon: ForgeIcons.search,
                message: l10n.detailNotFound,
                card: true,
              ),
            ],
          ),
          DetailReady() => _DetailBody(state, exerciseRoute),
        },
      ),
    );
  }
}

/// The page's ⋯: add the exercise to the workout in progress (or a new
/// one) or to a program, make it a favourite or not, and for a custom
/// exercise Edit, and Delete after asking.
class _MoreAction extends StatelessWidget {
  const _MoreAction(this.detail);

  final DetailReady detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercise = detail.exercise;
    final favorite = context.select(
      (FavoritesCubit cubit) => cubit.state.contains(exercise.id),
    );
    return ForgeAppBarAction.icon(
      icon: ForgeIcons.moreHoriz,
      label: l10n.detailMore,
      onPressed: () => showForgeMenu(
        context: context,
        items: [
          ForgeMenuItem(
            label: l10n.addToWorkout,
            icon: ForgeIcons.fitnessCenter,
            onTap: () => addToWorkout(context, exercise),
          ),
          ForgeMenuItem(
            label: l10n.addToProgram,
            icon: ForgeIcons.editCalendar,
            onTap: () => _addToProgram(context, exercise),
          ),
          ForgeMenuItem(
            label: favorite ? l10n.favoriteRemove : l10n.favoriteAdd,
            icon: ForgeIcons.star,
            onTap: () => context.read<FavoritesCubit>().toggle(exercise.id),
          ),
          if (exercise.isCustom) ...[
            ForgeMenuItem(
              label: l10n.customEdit,
              icon: ForgeIcons.edit,
              onTap: () => context.push(Routes.customExerciseEdit(exercise.id)),
            ),
            if (!detail.deleting)
              ForgeMenuItem(
                label: l10n.customDelete,
                icon: ForgeIcons.delete,
                destructive: true,
                onTap: () => _delete(context),
              ),
          ],
        ],
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
    final confirmed = await showForgeDialog<bool>(
      context: context,
      builder: (context) => ForgeDialog(
        title: l10n.customDeleteTitle,
        message: l10n.customDeleteBody,
        action: ForgeButton(
          label: l10n.customDelete,
          variant: ForgeButtonVariant.danger,
          onPressed: () => Navigator.pop(context, true),
        ),
        cancel: ForgeButton(
          label: l10n.cancel,
          variant: ForgeButtonVariant.secondary,
          onPressed: () => Navigator.pop(context, false),
        ),
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
    final colors = ForgeStyle.of(context).colors;
    final equipment = exercise.equipment.isEmpty
        ? null
        : [
            l10n.equipmentNames(exercise.equipment),
            for (final set in exercise.equipmentAlternatives)
              l10n.detailEquipmentOr(l10n.equipmentNames(set)),
          ].join('\n');
    // A custom exercise shows only its equipment here; the model names its
    // muscles and the line under it the logging type.
    final facts = [
      if (equipment != null) (l10n.detailEquipment, equipment),
      if (!exercise.isCustom) ...[
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
      ],
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.lg),
      children: [
        for (final part in [
          _MusclePreview(exercise),
          if (exercise.isCustom)
            Row(
              spacing: Gap.sm,
              children: [
                ForgeTag(l10n.customLabel),
                Expanded(
                  child: Text(
                    l10n.detailLoggedAs(
                      l10n.loggingTypeName(exercise.loggingType).toLowerCase(),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium!
                        .copyWith(color: colors.inkMuted),
                  ),
                ),
              ],
            ),
          if (facts.isNotEmpty)
            ListRowCard(
              children: [
                for (final (label, value) in facts)
                  ListRow(title: label, value: value),
              ],
            ),
          if (text.setup.isNotEmpty)
            SectionCard.plain(
              title: l10n.detailSetup,
              child: BenefitList.numbered(text.setup),
            ),
          if (text.execution.isNotEmpty)
            SectionCard.plain(
              title: l10n.detailExecution,
              child: BenefitList.numbered(text.execution),
            ),
          if (text.mistakes.isNotEmpty)
            SectionCard.plain(
              title: l10n.detailMistakes,
              child: _Bullets(text.mistakes),
            ),
          if (text.safety case final safety?)
            SectionCard.plain(
              title: l10n.detailSafety,
              child: _Bullets([safety]),
            ),
          if (text.cues.isNotEmpty)
            SectionCard.plain(
              title: l10n.detailCues,
              child: _Bullets(text.cues),
            ),
          if (exercise.note case final note? when note.isNotEmpty)
            SectionCard.plain(title: l10n.detailNote, child: Text(note)),
        ]) ...[part, const SizedBox(height: Gap.sm)],
        if (detail.variations.isNotEmpty || detail.alternatives.isNotEmpty)
          _Similar(detail, exerciseRoute),
      ],
    );
  }
}

/// The exercise's variations and alternatives as two groups, each with its
/// count and its first few names; the card opens a sheet listing them all.
class _Similar extends StatelessWidget {
  const _Similar(this.detail, this.exerciseRoute);

  final DetailReady detail;
  final String Function(String id) exerciseRoute;

  static const int _preview = 3;

  List<(String, List<Exercise>)> _groups(AppLocalizations l10n) => [
    if (detail.variations.isNotEmpty)
      (l10n.detailVariations(detail.variations.length), detail.variations),
    if (detail.alternatives.isNotEmpty)
      (
        l10n.detailAlternatives(detail.alternatives.length),
        detail.alternatives,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final muted = ForgeStyle.of(context).colors.inkMuted;
    return SectionCard(
      title: l10n.detailSimilar,
      detail: '${detail.variations.length + detail.alternatives.length}',
      onTap: () => _showAll(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.md,
        children: [
          for (final (label, exercises) in _groups(l10n))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Gap.xs,
              children: [
                Text(label, style: text.labelMedium!.copyWith(color: muted)),
                for (final exercise in exercises.take(_preview))
                  Text(
                    exercise.localized(context).name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Every variation and alternative, by group; a row closes the sheet and
  /// opens that exercise.
  Future<void> _showAll(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showForgeBottomSheet<void>(
      context: context,
      builder: (sheet) => ForgeBottomSheet(
        title: l10n.detailSimilar,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (label, exercises) in _groups(l10n)) ...[
                SectionLabel(label),
                ListRowCard(
                  children: [
                    for (final exercise in exercises)
                      ExerciseTile(
                        exercise,
                        onOpen: () {
                          Navigator.pop(sheet);
                          context.push(exerciseRoute(exercise.id));
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One line per item, each marked with a bullet.
class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.xs,
      children: [for (final item in items) Text(l10n.stepBullet(item))],
    );
  }
}

/// The page's shape in shimmering stand-ins: the model, the facts and two
/// cards.
class _Loading extends StatelessWidget {
  const _Loading();

  static const double _modelHeight = 200;

  @override
  Widget build(BuildContext context) {
    Widget card(List<double> widths) => ListRowCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Gap.sm,
            children: [
              for (final (i, width) in widths.indexed)
                SkeletonBar(widthFactor: width, height: i == 0 ? 14 : 10),
            ],
          ),
        ),
      ],
    );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
      children: [
        SkeletonBar(
          widthFactor: 1,
          height: _modelHeight,
          radius: ForgeStyle.of(context).radii.lg,
        ),
        const SizedBox(height: Gap.sm),
        ListRowCard(
          children: [for (var i = 0; i < 4; i++) ListRow.loading(index: i)],
        ),
        const SizedBox(height: Gap.sm),
        card(const [0.4, 0.9, 0.7, 0.8]),
        const SizedBox(height: Gap.sm),
        card(const [0.4, 0.6, 0.8]),
      ],
    );
  }
}

/// The model from the front and from the back side by side, with the worked
/// muscles coloured. Neither view takes gestures, so the page scrolls over
/// them. When the exercise has an animation, the card gets two tabs: the
/// animation with a chip per clip (the default), and the pair.
class _MusclePreview extends StatefulWidget {
  const _MusclePreview(this.exercise);

  final Exercise exercise;

  @override
  State<_MusclePreview> createState() => _MusclePreviewState();
}

class _MusclePreviewState extends State<_MusclePreview> {
  var _moving = true;

  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;
    if (exercise.isCustom) return _pair(context, null);
    return BlocProvider(
      create: (_) => sl<ExerciseMotionCubit>(param1: exercise.id)..load(),
      child: BlocBuilder<ExerciseMotionCubit, ExerciseMotionState>(
        builder: (context, motion) =>
            _pair(context, motion is MotionReady ? motion : null),
      ),
    );
  }

  Widget _pair(BuildContext context, MotionReady? motion) {
    final l10n = AppLocalizations.of(context);
    final exercise = widget.exercise;
    final title = l10n.muscleModelWorked;
    final main = exercise.mainMuscles;
    final secondary = exercise.secondaryMuscles;
    return switch (context.watch<BodyModelCubit>().state) {
      BodyModelLoading() => MuscleModelPair.loading(
        title: title,
        main: main,
        secondary: secondary,
      ),
      BodyModelFailed() => MuscleModelPair.failed(
        title: title,
        main: main,
        secondary: secondary,
        onRetry: context.read<BodyModelCubit>().load,
      ),
      BodyModelReady(:final model) when motion != null => MuscleModelPair(
        model: model,
        header: ForgeSegmentedControl<bool>(
          segments: [
            ForgeSegment(value: true, label: l10n.motionTab),
            ForgeSegment(value: false, label: l10n.musclesTab),
          ],
          selected: _moving,
          onChanged: (moving) => setState(() => _moving = moving),
        ),
        stage: _moving ? _Motion(motion, exercise) : null,
        main: main,
        secondary: secondary,
      ),
      BodyModelReady(:final model) => MuscleModelPair(
        model: model,
        title: title,
        main: main,
        secondary: secondary,
      ),
    };
  }
}

/// The animation, a chip per clip, and under the chips the picked mistake's
/// text, or that the form is correct, in a place two lines tall so the card
/// keeps its height.
class _Motion extends StatelessWidget {
  const _Motion(this.motion, this.exercise);

  final MotionReady motion;
  final Exercise exercise;

  static const double _height = 290;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = ForgeStyle.of(context).colors;
    final mistakes = exercise.localized(context).mistakes;
    final line = motion.clips[motion.selected].line;
    final mistake = line == null ? null : mistakes.elementAtOrNull(line);
    final small = Theme.of(context).textTheme.bodySmall!;
    final style = line == null
        ? small
        : small.copyWith(color: p.danger, fontWeight: FontWeight.w500);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        ExerciseMotionView(
          motion: motion,
          main: exercise.mainMuscles,
          secondary: exercise.secondaryMuscles,
          height: _height,
        ),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final (i, clip) in motion.clips.indexed)
              ForgeChip(
                label: clip.line == null
                    ? l10n.motionCorrect
                    : l10n.motionMistake(i),
                tone: clip.line == null
                    ? ForgeChipTone.success
                    : ForgeChipTone.danger,
                selected: i == motion.selected,
                showCheck: false,
                onPressed: () => context.read<ExerciseMotionCubit>().select(i),
              ),
          ],
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                2 *
                MediaQuery.textScalerOf(context).scale(style.fontSize!) *
                style.height!,
          ),
          child: Text(
            line == null
                ? l10n.motionCorrectForm
                : mistake == null
                ? ''
                : l10n.motionMistakeText(mistake),
            style: style,
          ),
        ),
      ],
    );
  }
}
