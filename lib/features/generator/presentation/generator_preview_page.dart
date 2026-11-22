import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/page_parts.dart';
import '../../../core/widgets/volume_band.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../profile/presentation/profile_questions.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_validation.dart';
import '../../programs/presentation/exercise_picker_page.dart';
import '../../programs/presentation/item_targets_sheet.dart';
import '../../programs/presentation/program_day_section.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/retyped_weights.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../volume/presentation/volume_charts.dart';
import '../domain/generator_answers.dart';
import '../domain/generated_program.dart';
import 'generator_preview_cubit.dart';

/// The program generated from [answers]: its weekly sets and days, each
/// exercise with a menu (swap, keep, sets and reps, remove), made again on
/// Regenerate around the kept ones, stored on Save and then opened.
class GeneratorPreviewPage extends StatelessWidget {
  const GeneratorPreviewPage({super.key, required this.answers});

  final GeneratorAnswers answers;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<GeneratorPreviewCubit>(
      param1: answers,
      param2: Localizations.localeOf(context).languageCode,
    ),
    child: const _PreviewView(),
  );
}

class _PreviewView extends StatelessWidget {
  const _PreviewView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<GeneratorPreviewCubit>();
    final answers = cubit.answers;
    return BlocConsumer<GeneratorPreviewCubit, GeneratorPreviewState>(
      listenWhen: (previous, current) =>
          previous.saveStatus != current.saveStatus ||
          previous.regenerateFailure != current.regenerateFailure,
      listener: (context, state) {
        if (state.regenerateFailure case final failure?) {
          showForgeSnackbar(
            context,
            message: failure is NetworkFailure
                ? l10n.generatorOffline
                : l10n.generatorRegenerateFailed,
            error: true,
          );
          cubit.regenerateFailureShown();
        }
        switch (state.saveStatus) {
          case SaveStatus.saved:
            context.go(Routes.program(state.savedId!, created: true));
          case SaveStatus.failed:
            showForgeSnackbar(
              context,
              message: switch (state.saveFailure) {
                NetworkFailure() => l10n.errorNetwork,
                AuthFailure() => l10n.generatorSaveSignedOut,
                NotFoundFailure() => l10n.generatorSaveLibraryLoading,
                ValidationFailure() => l10n.generatorSaveInvalid,
                _ => l10n.programSaveFailed,
              },
              error: true,
            );
            cubit.saveFailureShown();
          case SaveStatus.idle || SaveStatus.saving:
        }
      },
      builder: (context, state) {
        final program = state.program;
        final ready = state.status == PreviewStatus.ready && program != null;
        final saving = state.saveStatus == SaveStatus.saving;
        const padding = EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md);
        Widget error(String title, String message) => ListView(
          padding: padding,
          children: [
            ErrorView(
              title: title,
              message: message,
              retryLabel: l10n.retry,
              onRetry: cubit.retry,
              card: true,
            ),
          ],
        );
        return Scaffold(
          appBar: ForgeAppBar(title: l10n.generatorPreviewTitle),
          body: switch (state.status) {
            // The rows need the library to be named.
            PreviewStatus.building ||
            PreviewStatus.ready when state.libraryFailed => ListView(
              padding: padding,
              children: [
                ErrorView(
                  title: l10n.libraryLoadFailed,
                  message: l10n.loadFailedDetail,
                  retryLabel: l10n.retry,
                  onRetry: cubit.retryLibrary,
                  card: true,
                ),
              ],
            ),
            PreviewStatus.building => ListView(
              padding: padding,
              children: [
                SurfaceCard(
                  child: WorkingView(
                    title: l10n.generatorBuildingTitle,
                    message: l10n.generatorBuilding(
                      answers.daysPerWeek,
                      answers.sessionMinutes,
                    ),
                  ),
                ),
              ],
            ),
            PreviewStatus.offline => error(
              l10n.offlineTitle,
              l10n.generatorOffline,
            ),
            PreviewStatus.notPremium => error(
              l10n.generatorNotPremiumTitle,
              l10n.generatorNotPremium,
            ),
            PreviewStatus.unavailable => error(
              l10n.generatorUnavailableTitle,
              l10n.generatorUnavailable,
            ),
            PreviewStatus.failure => error(
              l10n.generatorFailed,
              l10n.loadFailedDetail,
            ),
            PreviewStatus.noProgram => ListView(
              padding: padding,
              children: [
                EmptyView(
                  icon: ForgeIcons.info,
                  message: l10n.generatorNoProgram,
                  actions: [
                    ForgeButton(
                      label: l10n.generatorChangeAnswers,
                      variant: ForgeButtonVariant.secondary,
                      onPressed: () => context.pop(),
                    ),
                  ],
                  card: true,
                ),
              ],
            ),
            PreviewStatus.ready => _Program(
              program: program!,
              answers: answers,
              state: state,
            ),
          },
          // Off while the program is being built, and Regenerate while it
          // is saved.
          bottomNavigationBar: switch (state.status) {
            PreviewStatus.building || PreviewStatus.ready
                when !state.libraryFailed =>
              ForgeBottomActionBar.sideBySide(
                secondary: ForgeButton(
                  label: l10n.generatorRegenerate,
                  variant: ForgeButtonVariant.secondary,
                  size: ForgeButtonSize.large,
                  onPressed: ready && state.saveStatus == SaveStatus.idle
                      ? cubit.regenerate
                      : null,
                ),
                primary: ForgeButton(
                  label: l10n.generatorSave,
                  size: ForgeButtonSize.large,
                  loading: saving,
                  onPressed: ready
                      ? () => cubit.save(
                          name: l10n.generatorProgramName(
                            program.splitName,
                            program.days.length,
                          ),
                        )
                      : null,
                ),
              ),
            _ => null,
          },
        );
      },
    );
  }
}

class _Program extends StatelessWidget {
  const _Program({
    required this.program,
    required this.answers,
    required this.state,
  });

  final GeneratedProgram program;
  final GeneratorAnswers answers;
  final GeneratorPreviewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ForgeStyle.of(context).colors;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    l10n.generatorHeading(
                      program.splitName,
                      program.days.length,
                    ),
                    style: ForgeStyle.of(context).heading,
                  ),
                  Text(
                    l10n.generatorAnswersLine(
                      l10n.goalName(answers.goal),
                      l10n.levelName(answers.level),
                      answers.sessionMinutes,
                    ),
                    style: text.bodySmall!.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ),
            if (state.uncovered.isNotEmpty)
              NoticeBanner.line(
                icon: ForgeIcons.warning,
                message: l10n.generatorUncovered(
                  l10n.muscleNames([
                    for (final muscle in Muscle.values)
                      if (state.uncovered.contains(muscle)) muscle,
                  ]),
                ),
              ),
            const _WeeklySets(),
            _Days(program: program, state: state),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              child: Text(
                l10n.generatorKeptNote,
                style: text.labelMedium!.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Each muscle the week works as a VolumeBand, busiest first, under the
/// week's working sets; counted by the app from the library.
class _WeeklySets extends StatelessWidget {
  const _WeeklySets();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Recounted with each edit and each library change.
    context.watch<GeneratorPreviewCubit>();
    context.watch<ExerciseCatalogueCubit>();
    final volume = context.read<GeneratorPreviewCubit>().volume;
    if (volume == null) return const SizedBox.shrink();
    final sets = [
      for (final entry in volume.ranked)
        if (entry.sets > 0) entry,
    ];
    final scale = volumeScale([for (final entry in sets) entry.sets]);
    return SectionCard(
      title: l10n.generatorWeeklySets,
      detail: l10n.generatorSetsTotal(volume.total),
      onTap: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          for (final entry in sets)
            VolumeBand(muscle: entry.muscle, sets: entry.sets, scale: scale),
        ],
      ),
    );
  }
}

/// The days as cards that open to their exercises, the first one open; so
/// again for each program Regenerate makes.
class _Days extends StatefulWidget {
  const _Days({required this.program, required this.state});

  final GeneratedProgram program;
  final GeneratorPreviewState state;

  @override
  State<_Days> createState() => _DaysState();
}

class _DaysState extends State<_Days> {
  var _open = {0};

  @override
  void didUpdateWidget(_Days oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.seed != oldWidget.state.seed) _open = {0};
  }

  @override
  Widget build(BuildContext context) {
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final catalogue = context.select(
      (ExerciseCatalogueCubit cubit) => cubit.state,
    );
    final exercises = catalogue is CatalogueReady
        ? {for (final e in catalogue.exercises) e.id: e}
        : const <String, Exercise>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        for (final (index, day) in widget.program.days.indexed)
          ProgramDayCard(
            day: day,
            index: index,
            open: _open.contains(index),
            onToggle: () => setState(() {
              if (!_open.remove(index)) _open.add(index);
            }),
            rows: [
              for (final (i, item) in day.items.indexed)
                _ItemRow(
                  day: index,
                  index: i,
                  item: item,
                  exercise: exercises[item.exerciseId],
                  kept: widget.state.isKept(index, item),
                  removable: day.items.length > 1,
                  unit: unit,
                ),
            ],
          ),
      ],
    );
  }
}

/// An exercise of a day: its name over its sets and reps ("· Kept" when
/// kept) and ⋯ with Swap, Keep when regenerating, Change sets and reps and
/// Remove.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.day,
    required this.index,
    required this.item,
    required this.exercise,
    required this.kept,
    required this.removable,
    required this.unit,
  });

  final int day;
  final int index;
  final ProgramItem item;
  final Exercise? exercise;
  final bool kept;
  final bool removable;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<GeneratorPreviewCubit>();
    final exercise = this.exercise;
    final summary = l10n.itemSummary(item, unit);
    return ListRow(
      title: exercise == null
          ? l10n.programExerciseLoading
          : exercise.localized(context).name,
      detail: summary,
      dataDetail: true,
      detailNote: kept ? l10n.generatorKept : null,
      trailing: Builder(
        builder: (context) => ForgeIconButton(
          icon: ForgeIcons.moreHoriz,
          label: l10n.programItemActions,
          onPressed: exercise == null
              ? null
              : () => showForgeMenu(
                  context: context,
                  items: [
                    ForgeMenuItem(
                      label: l10n.generatorSwap,
                      icon: ForgeIcons.sync,
                      onTap: () => _swap(context, cubit),
                    ),
                    ForgeMenuItem(
                      label: l10n.generatorKeep,
                      icon: ForgeIcons.history,
                      selected: kept,
                      onTap: () => cubit.toggleKept(day, index),
                    ),
                    ForgeMenuItem(
                      label: l10n.generatorChangeTargets,
                      icon: ForgeIcons.tune,
                      onTap: () => _editTargets(context, cubit, exercise),
                    ),
                    if (removable)
                      ForgeMenuItem(
                        label: l10n.programRemoveItem,
                        icon: ForgeIcons.delete,
                        destructive: true,
                        onTap: () => cubit.removeItem(day, index),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _swap(BuildContext context, GeneratorPreviewCubit cubit) async {
    final picked = await pickSwap(
      context,
      exerciseId: item.exerciseId,
      logged: 0,
      warmups: 0,
      picker: Routes.generatorPicker,
    );
    if (picked != null) cubit.swapItem(day, index, picked);
  }

  void _editTargets(
    BuildContext context,
    GeneratorPreviewCubit cubit,
    Exercise exercise,
  ) {
    final type = exercise.loggingType;
    unawaited(
      showForgeBottomSheet<void>(
        context: context,
        builder: (_) => BlocProvider.value(
          value: cubit,
          child: ItemTargetsSheet(
            title: exercise.localized(context).name,
            durationBased: type.isDurationBased,
            logsWeight: type.logsWeight,
            targets: _PreviewItemTargets(cubit, day, index, unit),
          ),
        ),
      ).then((_) => cubit.discardDraft()),
    );
  }
}

/// The preview's item at [_index] of day [_day], for [ItemTargetsSheet].
class _PreviewItemTargets implements ItemTargets {
  _PreviewItemTargets(this._cubit, this._day, this._index, this.weightUnit);

  final GeneratorPreviewCubit _cubit;
  final int _day;
  final int _index;
  final _retyped = RetypedWeights<int>();

  @override
  final WeightUnit weightUnit;

  /// The item with the change not valid yet, if there is one.
  @override
  ProgramItem get item => _cubit.state.itemAt(_day, _index)!;

  @override
  Set<ItemIssue> watchIssues(BuildContext context) =>
      context.select((GeneratorPreviewCubit cubit) {
        final item = cubit.state.itemAt(_day, _index);
        return item == null
            ? const <ItemIssue>{}
            : validateItem(item, cubit.loggingTypeOf(item.exerciseId));
      });

  void _edit(ProgramItem Function(ProgramItem item) change) =>
      _cubit.editItem(_day, _index, change);

  @override
  void setSets(String text) =>
      _edit((item) => item.copyWith(sets: _whole(text) ?? 0));

  @override
  void setRepMin(String text) =>
      _edit((item) => item.copyWith(repMin: () => _whole(text)));

  @override
  void setRepMax(String text) =>
      _edit((item) => item.copyWith(repMax: () => _whole(text)));

  @override
  void setDuration(String text) =>
      _edit((item) => item.copyWith(durationS: () => _whole(text)));

  @override
  void setRest(int seconds) => _edit((item) => item.copyWith(restS: seconds));

  @override
  void setTarget(String text) => _edit(
    (item) => item.copyWith(
      targetKg: () => _retyped.kg(0, text, weightUnit, item.targetKg),
    ),
  );

  static int? _whole(String text) {
    final value = int.tryParse(text.trim());
    // Text fields cap the length; this guards pasted text.
    return value == null || value.abs() > 1000000 ? null : value;
  }
}
