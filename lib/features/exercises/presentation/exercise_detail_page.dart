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
              _AddAction(state.exercise),
              if (state.exercise.isCustom) _CustomActions(state),
            ],
          ],
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

/// The one Add action: a menu adding to the workout in progress (or a new
/// one) or to a program.
class _AddAction extends StatelessWidget {
  const _AddAction(this.exercise);

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ForgeAppBarAction.text(
      label: l10n.detailAdd,
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
            icon: ForgeIcons.add,
            onTap: () => _addToProgram(context),
          ),
        ],
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
    final similar = [
      for (final other in detail.alternatives) (other, l10n.detailAlternative),
      for (final other in detail.variations) (other, l10n.detailVariation),
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
        if (similar.isNotEmpty) ...[
          SectionLabel(l10n.detailSimilar),
          ListRowCard(
            children: [
              for (final (other, relation) in similar)
                ExerciseTile(other, route: exerciseRoute, tag: relation),
            ],
          ),
        ],
      ],
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
