import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/muscle_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../programs/presentation/add_to_program.dart';
import '../../programs/presentation/add_to_program_cubit.dart';
import '../../workout/presentation/start_workout.dart';
import '../../workout/presentation/workout_editor_view.dart';
import '../domain/exercise.dart';
import '../domain/exercise_usecases.dart';
import 'body_model_cubit.dart';
import 'exercise_catalogue_cubit.dart';
import 'exercise_detail_cubit.dart';
import 'exercise_notes_cubit.dart';
import 'favorites_cubit.dart';
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
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => sl<ExerciseDetailCubit>(param1: exerciseId)),
      BlocProvider.value(value: sl<ExerciseNotesCubit>()),
    ],
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
          actions: [
            if (state is DetailReady) ...[
              _FavoriteAction(state.exercise.id),
              if (state.exercise.isCustom) _CustomActions(state),
            ],
          ],
        ),
        bottomNavigationBar: state is DetailReady
            ? _AddBar(state.exercise)
            : null,
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

/// The favourite star: an outline, filled once a favourite.
class _FavoriteAction extends StatelessWidget {
  const _FavoriteAction(this.exerciseId);

  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final favorite = context.select(
      (FavoritesCubit cubit) => cubit.state.contains(exerciseId),
    );
    return ForgeAppBarAction.icon(
      icon: ForgeIcons.star,
      label: favorite ? l10n.favoriteRemove : l10n.favoriteAdd,
      toggled: favorite,
      onPressed: () => context.read<FavoritesCubit>().toggle(exerciseId),
    );
  }
}

/// The page's bottom bar: add the exercise to the workout in progress (or
/// a new one), or to a program.
class _AddBar extends StatelessWidget {
  const _AddBar(this.exercise);

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ForgeBottomActionBar.stacked(
      primary: ForgeButton(
        label: l10n.addToWorkout,
        onPressed: () => addToWorkout(context, exercise),
      ),
      secondary: ForgeButton(
        label: l10n.addToProgram,
        variant: ForgeButtonVariant.secondary,
        onPressed: () => _addToProgram(context),
      ),
    );
  }

  Future<void> _addToProgram(BuildContext context) async {
    final cubit = sl<AddToProgramCubit>();
    await addToProgram(context, exercise, cubit);
    await cubit.close();
  }
}

/// A custom exercise's ⋯: Edit, and Delete after asking.
class _CustomActions extends StatelessWidget {
  const _CustomActions(this.detail);

  final DetailReady detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ForgeAppBarAction.icon(
      icon: ForgeIcons.moreHoriz,
      label: l10n.detailMore,
      onPressed: () => showForgeMenu(
        context: context,
        items: [
          ForgeMenuItem(
            label: l10n.customEdit,
            icon: ForgeIcons.edit,
            onTap: () =>
                context.push(Routes.customExerciseEdit(detail.exercise.id)),
          ),
          if (!detail.deleting)
            ForgeMenuItem(
              label: l10n.customDelete,
              icon: ForgeIcons.delete,
              destructive: true,
              onTap: () => _delete(context),
            ),
        ],
      ),
    );
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
          if (!exercise.isCustom) _OwnNote(exercise),
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

/// The user's own note on a catalogue exercise, edited in a sheet.
class _OwnNote extends StatelessWidget {
  const _OwnNote(this.exercise);

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final note = context.select(
      (ExerciseNotesCubit cubit) => cubit.state.of(exercise.id),
    );
    return SectionCard.plain(
      title: l10n.detailOwnNote,
      actionLabel: note == null ? l10n.detailOwnNoteAdd : l10n.customEdit,
      onAction: () => _edit(context, note),
      child: note == null ? null : Text(note),
    );
  }

  Future<void> _edit(BuildContext context, String? note) async {
    final l10n = AppLocalizations.of(context);
    final notes = context.read<ExerciseNotesCubit>();
    var text = note ?? '';
    final save = await showForgeBottomSheet<bool>(
      context: context,
      builder: (context) => ForgeBottomSheet(
        title: l10n.detailOwnNote,
        action: ForgeButton(
          label: l10n.customSave,
          size: ForgeButtonSize.large,
          onPressed: () => Navigator.pop(context, true),
        ),
        child: NoteField(
          initial: note,
          label: l10n.detailNote,
          hint: l10n.workoutNoteHint,
          maxLength: maxExerciseNoteLength,
          onChanged: (changed) => text = changed,
        ),
      ),
    );
    if (save != true) return;
    final failure = await notes.save(exercise.id, text);
    if (failure != null && context.mounted) {
      showForgeSnackbar(
        context,
        message: failure is NetworkFailure
            ? l10n.errorNetwork
            : l10n.detailOwnNoteSaveFailed,
        error: true,
      );
    }
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
/// them.
class _MusclePreview extends StatefulWidget {
  const _MusclePreview(this.exercise);

  final Exercise exercise;

  @override
  State<_MusclePreview> createState() => _MusclePreviewState();
}

class _MusclePreviewState extends State<_MusclePreview> {
  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
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
      BodyModelReady(:final model) => MuscleModelPair(
        model: model,
        title: title,
        main: main,
        secondary: secondary,
      ),
    };
  }
}
