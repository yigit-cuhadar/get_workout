import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/muscle_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../analytics/domain/analytics.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../strength/domain/strength.dart';
import '../../strength/presentation/exercise_strength_cubit.dart';
import '../../strength/presentation/strength_text.dart';
import '../../workout/domain/exercise_stats.dart';
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
          actions: [
            if (state is DetailReady) ...[
              _FavoriteAction(state.exercise),
              _MoreAction(state),
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

/// The star beside the ⋯: makes the exercise a favourite or not.
class _FavoriteAction extends StatelessWidget {
  const _FavoriteAction(this.exercise);

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final favorite = context.select(
      (FavoritesCubit cubit) => cubit.state.contains(exercise.id),
    );
    return ForgeAppBarAction.icon(
      icon: ForgeIcons.star,
      label: favorite ? l10n.favoriteRemove : l10n.favoriteAdd,
      toggled: favorite,
      onPressed: () => context.read<FavoritesCubit>().toggle(exercise.id),
    );
  }
}

/// The page's ⋯: add the exercise to the workout in progress (or a new
/// one) or to a program, and for a custom exercise Edit, and Delete after
/// asking.
class _MoreAction extends StatelessWidget {
  const _MoreAction(this.detail);

  final DetailReady detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercise = detail.exercise;
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
    final exercise = detail.exercise;
    if (exercise.isCustom) return _CustomBody(exercise);
    // Read here: the create callback must not look up inherited widgets.
    final unit = context.read<SettingsCubit>().state.settings.weightUnit;
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => sl<ExerciseMotionCubit>(param1: exercise.id)..load(),
        ),
        // Made when the Performance tab first shows.
        BlocProvider(
          create: (_) =>
              sl<ExerciseStrengthCubit>(param1: exercise.id, param2: unit)
                ..selectRange(StrengthRange.all),
        ),
      ],
      child: _CatalogueBody(detail, exerciseRoute),
    );
  }
}

/// The facts of [exercise] as label and value rows; a custom exercise has
/// only its equipment here, its tag line naming the logging type.
List<(String, String)> _facts(BuildContext context, Exercise exercise) {
  final l10n = AppLocalizations.of(context);
  final text = exercise.localized(context);
  final equipment = exercise.equipment.isEmpty
      ? null
      : [
          l10n.equipmentNames(exercise.equipment),
          for (final set in exercise.equipmentAlternatives)
            l10n.detailEquipmentOr(l10n.equipmentNames(set)),
        ].join('\n');
  return [
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
}

Widget _factsCard(List<(String, String)> facts) => ListRowCard(
  children: [
    for (final (label, value) in facts) ListRow(title: label, value: value),
  ],
);

/// A custom exercise: its muscles, its tag and logging type, its equipment
/// and its note; no animation, tabs or performance.
class _CustomBody extends StatefulWidget {
  const _CustomBody(this.exercise);

  final Exercise exercise;

  @override
  State<_CustomBody> createState() => _CustomBodyState();
}

class _CustomBodyState extends State<_CustomBody> {
  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercise = widget.exercise;
    final colors = ForgeStyle.of(context).colors;
    final facts = _facts(context, exercise);
    final title = l10n.muscleModelWorked;
    final main = exercise.mainMuscles;
    final secondary = exercise.secondaryMuscles;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.lg),
      children: [
        for (final part in [
          switch (context.watch<BodyModelCubit>().state) {
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
          },
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
          if (facts.isNotEmpty) _factsCard(facts),
          if (exercise.note case final note? when note.isNotEmpty)
            SectionCard.plain(title: l10n.detailNote, child: Text(note)),
        ]) ...[part, const SizedBox(height: Gap.sm)],
      ],
    );
  }
}

enum _Tab { howTo, details, performance }

/// A catalogue exercise: the stage edge to edge, a card per form under it,
/// then the How to do it, Details and Performance tabs, their bar pinned
/// under the app bar once it reaches it.
class _CatalogueBody extends StatefulWidget {
  const _CatalogueBody(this.detail, this.exerciseRoute);

  final DetailReady detail;
  final String Function(String id) exerciseRoute;

  @override
  State<_CatalogueBody> createState() => _CatalogueBodyState();
}

class _CatalogueBodyState extends State<_CatalogueBody>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: _Tab.values.length, vsync: this)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// The mistakes no form card plays, under their title: with an
  /// animation the ones it cannot show ("Also watch for"), without one all
  /// of them; none while the animation loads.
  (String, List<String>)? _unplayed(List<String> mistakes) {
    final l10n = AppLocalizations.of(context);
    final List<String> lines;
    final String title;
    switch (context.watch<ExerciseMotionCubit>().state) {
      case MotionLoading():
        return null;
      case MotionReady(:final clips):
        final shown = {for (final clip in clips) ?clip.line};
        lines = [
          for (final (i, line) in mistakes.indexed)
            if (!shown.contains(i)) line,
        ];
        title = l10n.detailMistakesAlso;
      case MotionNone() || MotionFailed():
        lines = mistakes;
        title = l10n.detailMistakes;
    }
    return lines.isEmpty ? null : (title, lines);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = widget.detail;
    final exercise = detail.exercise;
    final text = exercise.localized(context);
    final tab = _Tab.values[_tabs.index];
    const side = EdgeInsets.symmetric(horizontal: Gap.md);
    final content = switch (tab) {
      _Tab.howTo => [
        if (text.setup.isNotEmpty || text.execution.isNotEmpty)
          SectionCard.plain(
            title: l10n.detailExecution,
            child: _Steps(setup: text.setup, execution: text.execution),
          ),
        if (_unplayed(text.mistakes) case (final title, final lines))
          SectionCard.plain(
            title: title,
            icon: ForgeIcons.warning,
            child: _Bullets(lines),
          ),
        if (text.cues.isNotEmpty)
          SectionCard.plain(
            title: l10n.detailCues,
            icon: ForgeIcons.lightbulb,
            child: _Bullets(text.cues),
          ),
        if (text.safety case final safety?)
          SectionCard.plain(
            title: l10n.detailSafety,
            icon: ForgeIcons.warning,
            warning: true,
            child: _Bullets([safety]),
          ),
      ],
      _Tab.details => [
        _factsCard(_facts(context, exercise)),
        if (detail.variations.isNotEmpty || detail.alternatives.isNotEmpty)
          _Similar(detail, widget.exerciseRoute),
      ],
      _Tab.performance => [_Performance(exercise)],
    };
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Hero(exercise)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.sm),
          sliver: SliverToBoxAdapter(child: _FormCards(exercise)),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarHeader(
            TabBar(
              controller: _tabs,
              tabs: [
                Tab(text: l10n.detailExecution),
                Tab(text: l10n.detailDetailsTab),
                Tab(text: l10n.detailPerformanceTab),
              ],
            ),
            ForgeStyle.of(context).colors.ground,
          ),
        ),
        SliverPadding(
          padding: side.copyWith(top: Gap.sm, bottom: Gap.lg),
          sliver: SliverList.list(
            children: [
              for (final (i, part) in content.indexed) ...[
                if (i > 0) const SizedBox(height: Gap.sm),
                part,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The tab bar on the page's ground, so content scrolls under it unseen.
class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader(this.bar, this.ground);

  final TabBar bar;
  final Color ground;

  @override
  double get minExtent => bar.preferredSize.height;

  @override
  double get maxExtent => bar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(color: ground, child: bar);

  @override
  bool shouldRebuild(_TabBarHeader old) =>
      old.bar != bar || old.ground != ground;
}

/// The user's own sets with [exercise]: the last time and the best records
/// as figures, the latest workouts (each opening its workout), and See
/// progress opening the strength page. Never done, it says so and offers
/// Add to workout.
class _Performance extends StatelessWidget {
  const _Performance(this.exercise);

  final Exercise exercise;

  static const _shown = 5;
  static const _figures = {RecordKind.bestE1rm, RecordKind.heaviestWeight};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ExerciseStrengthCubit>();
    final state = context.watch<ExerciseStrengthCubit>().state;
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final type = exercise.loggingType;
    final Widget body = switch (state.status) {
      ExerciseStrengthStatus.loading => ListRowCard(
        children: [for (var i = 0; i < 3; i++) ListRow.loading(index: i)],
      ),
      ExerciseStrengthStatus.failure => ErrorView(
        title: l10n.strengthLoadFailed,
        message: l10n.loadFailedDetail,
        retryLabel: l10n.retry,
        onRetry: cubit.retry,
        card: true,
      ),
      ExerciseStrengthStatus.ready when !state.trained => EmptyView(
        icon: ForgeIcons.history,
        title: l10n.performanceEmptyTitle,
        message: l10n.performanceEmptyMessage,
        card: true,
        actions: [
          ForgeButton(
            label: l10n.addToWorkout,
            onPressed: () => addToWorkout(context, exercise),
          ),
        ],
      ),
      ExerciseStrengthStatus.ready => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.sm,
              children: [
                if (state.sessions.firstOrNull case final last?)
                  Expanded(
                    child: StatTile.figure(
                      figure: l10n.sessionText(last, type, unit),
                      caption: l10n.performanceLastTime(
                        l10n.shortDate(last.date),
                      ),
                    ),
                  ),
                for (final entry in state.records)
                  if (_figures.contains(entry.kind))
                    Expanded(
                      child: StatTile.figure(
                        figure: l10n.recordValue(entry, type, unit),
                        caption: l10n.recordName(entry.kind),
                      ),
                    ),
              ],
            ),
          ),
          if (state.sessions.isNotEmpty)
            ListRowCard(
              children: [
                for (final session in state.sessions.take(_shown))
                  ListRow(
                    title: l10n.sessionText(session, type, unit),
                    dataTitle: true,
                    detail: l10n.sessionDetail(session),
                    end: ListRowEnd.chevron,
                    onTap: () =>
                        context.go(Routes.calendarWorkout(session.workoutId)),
                  ),
              ],
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ForgeButton(
              label: l10n.performanceSeeProgress,
              variant: ForgeButtonVariant.text,
              onPressed: () => context.go(Routes.strengthExercise(exercise.id)),
            ),
          ),
        ],
      ),
    };
    return BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (previous, current) =>
          previous.settings.weightUnit != current.settings.weightUnit,
      listener: (_, settings) => cubit.setUnit(settings.settings.weightUnit),
      child: body,
    );
  }
}

/// Setup and the movement as numbered steps, each under its own heading
/// when the exercise has both.
class _Steps extends StatelessWidget {
  const _Steps({required this.setup, required this.execution});

  final List<String> setup;
  final List<String> execution;

  @override
  Widget build(BuildContext context) {
    if (setup.isEmpty || execution.isEmpty) {
      return BenefitList.numbered(setup.isEmpty ? execution : setup);
    }
    final l10n = AppLocalizations.of(context);
    final heading = Theme.of(context).textTheme.labelLarge!
        .copyWith(color: ForgeStyle.of(context).colors.inkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.md,
      children: [
        Text(l10n.detailSetup, style: heading),
        BenefitList.numbered(setup),
        const Divider(height: 1),
        Text(l10n.detailMovement, style: heading),
        BenefitList.numbered(execution),
      ],
    );
  }
}

/// The exercise's variations and alternatives, each group under its label
/// with its count, its first few as library rows (muscles and equipment,
/// the star, and Easier or Harder when the level differs from this
/// exercise's) and, when it has more, See all opening the whole group in a
/// sheet. A row opens that exercise in the same tab.
class _Similar extends StatelessWidget {
  const _Similar(this.detail, this.exerciseRoute);

  final DetailReady detail;
  final String Function(String id) exerciseRoute;

  static const int _preview = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = [
      if (detail.variations.isNotEmpty)
        (l10n.detailVariations(detail.variations.length), detail.variations),
      if (detail.alternatives.isNotEmpty)
        (
          l10n.detailAlternatives(detail.alternatives.length),
          detail.alternatives,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        for (final (label, exercises) in groups)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(label),
              ListRowCard(
                children: [
                  for (final exercise in exercises.take(_preview))
                    _tile(context, exercise),
                  if (exercises.length > _preview)
                    ListRow(
                      title: l10n.detailSeeAllCount(exercises.length),
                      end: ListRowEnd.chevron,
                      onTap: () => _showAll(context, label, exercises),
                    ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  /// [exercise] as a library row; [onOpen] in place of opening it here.
  Widget _tile(
    BuildContext context,
    Exercise exercise, {
    VoidCallback? onOpen,
  }) {
    final l10n = AppLocalizations.of(context);
    final here = detail.exercise.level;
    final level = exercise.level;
    return ExerciseTile(
      exercise,
      showFavorite: true,
      route: exerciseRoute,
      onOpen: onOpen,
      tag: here == null || level == null || level == here
          ? null
          : level.index < here.index
          ? l10n.similarEasier
          : l10n.similarHarder,
    );
  }

  /// The whole group; a row closes the sheet and opens that exercise.
  Future<void> _showAll(
    BuildContext context,
    String label,
    List<Exercise> exercises,
  ) => showForgeBottomSheet<void>(
    context: context,
    builder: (sheet) => ForgeBottomSheet(
      title: label,
      child: SingleChildScrollView(
        child: ListRowCard(
          children: [
            for (final exercise in exercises)
              _tile(
                context,
                exercise,
                onOpen: () {
                  Navigator.pop(sheet);
                  context.push(exerciseRoute(exercise.id));
                },
              ),
          ],
        ),
      ),
    ),
  );
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

/// The stage edge to edge under the app bar: the animation (Movement) or
/// the still front and back (Muscles), Movement / Muscles in its corner
/// when the exercise has an animation. Without one, the still pair alone.
class _Hero extends StatefulWidget {
  const _Hero(this.exercise);

  final Exercise exercise;

  static const double height = 380;

  /// The still pair's width before it is scaled into the stage.
  static const double figuresWidth = 320;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  var _moving = true;

  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = ForgeStyle.of(context).colors;
    final exercise = widget.exercise;
    final main = exercise.mainMuscles;
    final secondary = exercise.secondaryMuscles;
    final motion = context.watch<ExerciseMotionCubit>().state;
    final ready = motion is MotionReady ? motion : null;
    // Room above the still pair for Movement / Muscles.
    final top = ready == null
        ? Gap.md
        : Gap.sm * 2 + ForgeSegmentedControl.height;
    // The still pair is scaled into the stage's box, so Movement and
    // Muscles take the same height and nothing below moves.
    Widget figures(Model3D? model) => Padding(
      padding: EdgeInsets.fromLTRB(Gap.md, top, Gap.md, Gap.md),
      child: FittedBox(
        child: SizedBox(
          width: _Hero.figuresWidth,
          child: MuscleFigures(model: model, main: main, secondary: secondary),
        ),
      ),
    );
    // The animation's stage, then its hint line under it.
    final hint = Theme.of(context).textTheme.labelMedium!;
    final height =
        _Hero.height +
        Gap.sm +
        MediaQuery.textScalerOf(context).scale(hint.fontSize!) * hint.height! +
        Gap.sm;
    final stage = switch (context.watch<BodyModelCubit>().state) {
      BodyModelFailed() => Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: ErrorView(
          title: l10n.muscleModelFailedTitle,
          message: l10n.muscleModelPairFailedDetail,
          retryLabel: l10n.retry,
          onRetry: context.read<BodyModelCubit>().load,
          compact: true,
        ),
      ),
      BodyModelLoading() => figures(null),
      BodyModelReady() when motion is MotionLoading => figures(null),
      BodyModelReady() when ready != null && _moving => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: ExerciseMotionView(
          motion: ready,
          main: main,
          secondary: secondary,
          height: _Hero.height,
        ),
      ),
      BodyModelReady(:final model) => figures(model),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Stack(
        children: [
          SizedBox(height: height, width: double.infinity, child: stage),
          if (ready != null)
            PositionedDirectional(
              top: Gap.sm,
              start: Gap.md,
              width: 200,
              child: ForgeSegmentedControl<bool>(
                segments: [
                  ForgeSegment(value: true, label: l10n.motionTab),
                  ForgeSegment(value: false, label: l10n.musclesTab),
                ],
                selected: _moving,
                onChanged: (moving) => setState(() => _moving = moving),
              ),
            ),
        ],
      ),
    );
  }
}

/// A card per form under the stage, swiped sideways: the correct form with
/// its cues, then each common mistake with its line. The card in view
/// plays on the stage; a mistake without an animation leaves the correct
/// form playing and says so. Dots under the cards mark the one in view;
/// the worked muscles' legend closes the part.
class _FormCards extends StatefulWidget {
  const _FormCards(this.exercise);

  final Exercise exercise;

  @override
  State<_FormCards> createState() => _FormCardsState();
}

class _FormCardsState extends State<_FormCards> {
  final _pages = PageController(viewportFraction: 0.88);
  var _current = 0;

  static const int _bodyLines = 3;
  static const double _border = 1.5;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    final p = style.colors;
    final textTheme = Theme.of(context).textTheme;
    final exercise = widget.exercise;
    final text = exercise.localized(context);
    final motion = context.watch<ExerciseMotionCubit>().state;
    final legend = MuscleLegend(
      main: exercise.mainMuscles,
      secondary: exercise.secondaryMuscles,
    );
    // Without an animation there is nothing for a card to play: the
    // mistakes are on How to do it.
    if (motion is! MotionReady) return legend;
    final forms = [for (final clip in motion.clips) clip.line];

    final scale = MediaQuery.textScalerOf(context);
    final body = textTheme.bodyMedium!;
    final title = textTheme.titleSmall!;
    double lines(TextStyle style, int count) =>
        scale.scale(style.fontSize!) * style.height! * count;
    // The padding and the picked card's border on both sides, then its lines.
    final height =
        2 * (14 + _border) +
        lines(title, 1).clamp(24, double.infinity) +
        Gap.sm +
        lines(body, _bodyLines);

    Widget card(int index) {
      final line = forms[index];
      final selected = index == _current;
      final tone = line == null ? p.success : p.danger;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: Gap.sm),
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            onTap: () => _pages.animateToPage(
              index,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(style.radii.lg),
                border: Border.all(
                  color: selected ? tone : p.line,
                  width: selected ? _border : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.sm,
                children: [
                  Row(
                    spacing: 10,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.lerp(p.surface, tone, 0.14),
                        ),
                        child: line == null
                            ? ForgeIcon(ForgeIcons.check, size: 14, color: tone)
                            : Text(
                                '${line + 1}',
                                style: style.data.copyWith(
                                  fontSize: 12,
                                  color: tone,
                                ),
                              ),
                      ),
                      Expanded(
                        child: Text(
                          line == null
                              ? l10n.motionCorrectForm
                              : l10n.motionMistake(line + 1),
                          style: title.copyWith(color: p.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    line == null
                        ? text.cues.map(l10n.stepBullet).join('\n')
                        : text.mistakes[line],
                    style: body,
                    maxLines: _bodyLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _pages,
            padEnds: false,
            itemCount: forms.length,
            onPageChanged: (index) {
              setState(() => _current = index);
              context.read<ExerciseMotionCubit>().select(index);
            },
            itemBuilder: (context, index) => card(index),
          ),
        ),
        ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: [
              for (var i = 0; i < forms.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == _current ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _current ? p.ink : p.lineStrong,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Gap.xs),
        legend,
      ],
    );
  }
}
