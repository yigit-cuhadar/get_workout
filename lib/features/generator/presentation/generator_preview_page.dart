import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/page_parts.dart';
import '../../../core/widgets/volume_band.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
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
import '../domain/program_generator.dart';
import 'generator_preview_cubit.dart';
import 'generator_text.dart';

/// The program generated from [answers]: its weekly sets and days, each
/// exercise with a menu (swap, keep, sets and reps, remove), made again on
/// Regenerate around the kept ones, stored on Save and then opened.
class GeneratorPreviewPage extends StatelessWidget {
  const GeneratorPreviewPage({super.key, required this.answers});

  final GeneratorAnswers answers;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<GeneratorPreviewCubit>(param1: answers),
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
          previous.saveStatus != current.saveStatus,
      listener: (context, state) {
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
        return Scaffold(
          appBar: ForgeAppBar(title: l10n.generatorPreviewTitle),
          body: switch (state.status) {
            PreviewStatus.loading => ListView(
              padding: padding,
              children: [
                SurfaceCard(
                  child: WorkingView(
                    title: l10n.generatorBuildingTitle,
                    message: l10n.generatorBuilding(
                      answers.daysPerWeek,
                      l10n.splitName(splitFor(answers)),
                      answers.sessionMinutes,
                    ),
                  ),
                ),
              ],
            ),
            PreviewStatus.libraryFailed => ListView(
              padding: padding,
              children: [
                SurfaceCard(
                  child: ErrorView(
                    title: l10n.libraryLoadFailed,
                    message: l10n.loadFailedDetail,
                    retryLabel: l10n.retry,
                    onRetry: cubit.retry,
                  ),
                ),
              ],
            ),
            PreviewStatus.impossible => ListView(
              padding: padding,
              children: [
                SurfaceCard(
                  child: EmptyView(
                    icon: ForgeIcons.info,
                    message: l10n.generationIssueText(state.issue!),
                    actions: [
                      ForgeButton(
                        label: l10n.generatorChangeAnswers,
                        variant: ForgeButtonVariant.secondary,
                        onPressed: () => context.pop(),
                      ),
                    ],
                  ),
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
            PreviewStatus.loading ||
            PreviewStatus.ready => ForgeBottomActionBar.sideBySide(
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
                          l10n.splitName(program.split),
                          answers.daysPerWeek,
                        ),
                        dayName: l10n.generatedDayName,
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
                      l10n.splitName(program.split),
                      answers.daysPerWeek,
                    ),
                    style: text.headlineSmall,
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
            if (program.uncovered.isNotEmpty)
              NoticeBanner.line(
                icon: ForgeIcons.warning,
                message: l10n.generatorUncovered(
                  l10n.muscleNames(program.uncovered),
                ),
              ),
            _WeeklySets(program),
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

/// Each target muscle's weekly sets as a VolumeBand, under the week's
/// working sets.
class _WeeklySets extends StatelessWidget {
  const _WeeklySets(this.program);

  final GeneratedProgram program;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sets = {
      for (final muscle in program.targets.keys)
        muscle: program.weeklySets[muscle] ?? 0.0,
    };
    final scale = volumeScale(sets.values);
    final total = [for (final day in program.days) ...day.items]
        .fold(0, (sum, item) => sum + item.sets);
    return SectionCard(
      title: l10n.generatorWeeklySets,
      detail: l10n.generatorSetsTotal(total),
      onTap: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          for (final MapEntry(key: muscle, value: count) in sets.entries)
            VolumeBand(muscle: muscle, sets: count, scale: scale),
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
    final l10n = AppLocalizations.of(context);
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
            day: ProgramDay(name: l10n.generatedDayName(day), items: day.items),
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
        builder: (context) => Semantics(
          button: true,
          label: l10n.programItemActions,
          excludeSemantics: true,
          child: InkResponse(
            onTap: exercise == null
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
            child: SizedBox.square(
              dimension: ForgeTheme.tapMin,
              child: Center(
                child: ForgeIcon(
                  ForgeIcons.moreHoriz,
                  size: 20,
                  color: ForgeStyle.of(context).colors.inkMuted,
                ),
              ),
            ),
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
      ),
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

  @override
  ProgramItem get item => _cubit.state.program!.days[_day].items[_index];

  @override
  Set<ItemIssue> watchIssues(BuildContext context) =>
      context.select((GeneratorPreviewCubit cubit) {
        final item = cubit.state.program?.days
            .elementAtOrNull(_day)
            ?.items
            .elementAtOrNull(_index);
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
