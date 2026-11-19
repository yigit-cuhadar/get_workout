import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/grouping.dart';
import '../../../core/max_length_formatter.dart';
import '../../../core/page_parts.dart';
import '../../../core/unsaved_changes.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/program.dart';
import '../domain/program_editing.dart';
import '../domain/program_validation.dart';
import 'exercise_picker_page.dart';
import 'item_targets_sheet.dart';
import 'program_builder_cubit.dart';
import 'program_text.dart';
import 'widgets/builder_row.dart';

typedef _Picker = String Function({required int max, required bool multiple});

/// Creates a program, or edits program [programId].
class ProgramBuilderPage extends StatelessWidget {
  const ProgramBuilderPage({
    super.key,
    this.programId,
    this.returns = false,
    this.picker = Routes.exercisePicker,
  });

  final String? programId;

  /// Pushed above the page it was opened from: saving or closing returns
  /// there instead of opening the new program or the programs.
  final bool returns;

  /// The exercise picker above this page, in its tab.
  final String Function({required int max, required bool multiple}) picker;

  @override
  Widget build(BuildContext context) {
    final unit = context.read<SettingsCubit>().state.settings.weightUnit;
    return BlocProvider(
      create: (_) => sl<ProgramBuilderCubit>(param1: programId, param2: unit),
      child: _BuilderView(returns: returns, picker: picker),
    );
  }
}

class _BuilderView extends StatelessWidget {
  const _BuilderView({required this.returns, required this.picker});

  final bool returns;
  final _Picker picker;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProgramBuilderCubit>();
    return UnsavedChangesGuard(
      hasChanges: () => cubit.hasChanges,
      confirmDiscard: () => _confirmDiscard(context),
      child: BlocConsumer<ProgramBuilderCubit, ProgramBuilderState>(
        listenWhen: (previous, current) =>
            previous.status != current.status || current.adjusted.isNotEmpty,
        listener: (context, state) {
          if (state.adjusted.isNotEmpty) {
            final names = [
              for (final id in state.adjusted)
                state.exercises[id]?.localized(context).name ?? id,
            ];
            showForgeSnackbar(
              context,
              message: l10n.programAdjusted(l10n.inlineList(names)),
            );
            cubit.adjustedShown();
            return;
          }
          switch (state.status) {
            case ProgramBuilderStatus.saved when cubit.isEditing || returns:
              context.pop();
            case ProgramBuilderStatus.closed when returns:
              context.pop();
            case ProgramBuilderStatus.saved:
              context.go(Routes.program(state.savedId!, created: true));
            case ProgramBuilderStatus.closed:
              context.go(Routes.programs);
            case ProgramBuilderStatus.saveFailed:
              showForgeSnackbar(
                context,
                message: state.failure is NetworkFailure
                    ? l10n.errorNetwork
                    : l10n.programSaveFailed,
                error: true,
              );
            default:
          }
        },
        builder: (context, state) {
          final catalogue = context.watch<ExerciseCatalogueCubit>().state;
          final ready =
              state.status != ProgramBuilderStatus.loading &&
              catalogue is CatalogueReady;
          final shown =
              ready &&
              state.status != ProgramBuilderStatus.notFound &&
              state.status != ProgramBuilderStatus.loadFailed;
          return PopScope(
            canPop: !state.dirty,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              if (await UnsavedChangesGuard.ask(context) && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Scaffold(
              appBar: ForgeAppBar(
                title: cubit.isEditing
                    ? l10n.programEditTitle
                    : l10n.programNew,
                actions: [
                  if (shown)
                    ForgeAppBarAction.text(
                      label: l10n.programSave,
                      onPressed: state.isBusy ? null : cubit.save,
                    ),
                ],
              ),
              body: switch (state.status) {
                ProgramBuilderStatus.notFound => EmptyView(
                  message: l10n.programNotFound,
                ),
                ProgramBuilderStatus.loadFailed => ErrorView(
                  title: l10n.programsLoadFailedTitle,
                  message: l10n.loadFailedDetail,
                  retryLabel: l10n.retry,
                  onRetry: cubit.load,
                ),
                _ => switch (catalogue) {
                  CatalogueFailed() => ErrorView(
                    title: l10n.libraryLoadFailed,
                    message: l10n.loadFailedDetail,
                    retryLabel: l10n.retry,
                    onRetry: context.read<ExerciseCatalogueCubit>().retry,
                  ),
                  _ when !ready => const _Skeleton(),
                  _ => _Form(picker: picker),
                },
              },
            ),
          );
        },
      ),
    );
  }

  static Future<bool> _confirmDiscard(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final name = context.read<ProgramBuilderCubit>().state.program.name.trim();
    final discard = await showForgeDialog<bool>(
      context: context,
      builder: (context) => ForgeDialog(
        title: l10n.programDiscardTitle,
        message: name.isEmpty
            ? l10n.programDiscardBody
            : l10n.builderDiscardNamed(name),
        action: ForgeButton(
          label: l10n.programDiscard,
          variant: ForgeButtonVariant.danger,
          onPressed: () => Navigator.pop(context, true),
        ),
        cancel: ForgeButton(
          label: l10n.programKeepEditing,
          variant: ForgeButtonVariant.secondary,
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
    );
    return discard == true;
  }
}

/// The page while the program or the library loads: the name, the day
/// chips and two cards of rows as skeletons.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    Widget card(List<(double, double)> bars) => SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.sm,
        children: [
          for (final (width, height) in bars)
            SkeletonBar(widthFactor: width, height: height),
        ],
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          card([(0.25, 14), (0.9, 10)]),
          Row(
            spacing: 6,
            children: [
              for (final width in [64.0, 56.0, 56.0, 72.0])
                SkeletonBar(
                  width: width,
                  height: 36,
                  radius: ForgeRadii.button,
                ),
            ],
          ),
          card([(0.5, 14), (0.7, 10), (0.45, 10)]),
          card([(0.5, 14), (0.65, 10), (0.45, 10)]),
        ],
      ),
    );
  }
}

/// The program's name and length, its day chips, then the selected day's
/// items, which reorder by dragging.
class _Form extends StatefulWidget {
  const _Form({required this.picker});

  final _Picker picker;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final ProgramBuilderCubit _cubit = context.read<ProgramBuilderCubit>();
  late final _name = TextEditingController(text: _cubit.state.program.name);
  late final _weeks = TextEditingController(
    text: _cubit.state.program.lengthWeeks?.toString() ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _weeks.dispose();
    super.dispose();
  }

  /// Adds a day, then asks for its name.
  Future<void> _addDay() async {
    final days = _cubit.state.program.days.length;
    _cubit.addDay();
    if (_cubit.state.program.days.length == days) return;
    await _rename(days);
  }

  Future<void> _rename(int index) async {
    final day = _cubit.state.program.days[index];
    final name = await showForgeDialog<String>(
      context: context,
      builder: (_) => _RenameDayDialog(name: day.name, number: index + 1),
    );
    if (name != null) _cubit.renameDay(index, name);
  }

  Future<void> _delete(int index) async {
    final l10n = AppLocalizations.of(context);
    final count = _cubit.state.program.days[index].items.length;
    if (count > 0) {
      final confirmed = await showForgeDialog<bool>(
        context: context,
        builder: (context) => ForgeDialog(
          title: l10n.programDeleteDayTitle,
          message: l10n.builderDeleteDayBody(count),
          action: ForgeButton(
            label: l10n.programDeleteDay,
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
      if (confirmed != true) return;
    }
    _cubit.deleteDay(index);
  }

  /// The day menu under day [index]'s chip ([anchor]).
  void _dayMenu(BuildContext anchor, int index) {
    final l10n = AppLocalizations.of(context);
    final state = _cubit.state;
    final count = state.program.days.length;
    showForgeMenu(
      context: anchor,
      items: [
        ForgeMenuItem(
          label: l10n.builderRenameDay,
          icon: ForgeIcons.edit,
          onTap: () => _rename(index),
        ),
        if (state.canAddDay)
          ForgeMenuItem(
            label: l10n.builderDuplicateDay,
            icon: ForgeIcons.contentCopy,
            onTap: () => _cubit.duplicateDay(index, l10n.builderDayCopy),
          ),
        if (index > 0)
          ForgeMenuItem(
            label: l10n.programMoveDayEarlier,
            icon: ForgeIcons.arrowUpward,
            onTap: () => _cubit.moveDay(index, index - 1),
          ),
        if (index < count - 1)
          ForgeMenuItem(
            label: l10n.programMoveDayLater,
            icon: ForgeIcons.arrowDownward,
            onTap: () => _cubit.moveDay(index, index + 1),
          ),
        if (count > 1)
          ForgeMenuItem(
            label: l10n.programDeleteDay,
            icon: ForgeIcons.delete,
            destructive: true,
            onTap: () => _delete(index),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final text = Theme.of(context).textTheme;
    final state = context.watch<ProgramBuilderCubit>().state;
    final validation = state.validation;
    final day = state.day!;
    final dayIndex = state.selectedDay;
    final items = day.items;
    String? programError(Set<ProgramIssue> issues) => validation.program
        .where(issues.contains)
        .map(l10n.programIssueText)
        .firstOrNull;
    final dayIssues = validation.dayIssues(dayIndex);
    final daysError = programError({
      ProgramIssue.noDays,
      ProgramIssue.tooManyDays,
    });
    final lengthError = programError({ProgramIssue.lengthWeeksOutOfRange});
    Widget danger(String message) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
      child: Text(
        message,
        style: text.bodySmall!.copyWith(color: colors.danger),
      ),
    );
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.sm),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.sm,
              children: [
                ForgeTextField(
                  label: l10n.programName,
                  controller: _name,
                  inputFormatters: [
                    maxLengthFormatter(ProgramLimits.maxNameLength),
                  ],
                  errorText: programError({
                    ProgramIssue.nameMissing,
                    ProgramIssue.nameTooLong,
                  }),
                  onChanged: _cubit.setName,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Gap.xs,
                  children: [
                    ForgeTextField(
                      label: l10n.programLength,
                      controller: _weeks,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      errorText: lengthError,
                      onChanged: _cubit.setLengthWeeks,
                    ),
                    if (lengthError == null)
                      Text(
                        l10n.programLengthHelp,
                        style: text.bodySmall!.copyWith(color: colors.inkMuted),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (i, other) in state.program.days.indexed)
                      Builder(
                        builder: (anchor) => ForgeChip(
                          label: l10n.dayName(other, i),
                          selected: i == dayIndex,
                          showCheck: false,
                          leading:
                              validation.dayIssues(i).isNotEmpty ||
                                  validation.items.keys.any(
                                    (ref) => ref.day == i,
                                  )
                              ? ForgeIcon(
                                  ForgeIcons.error,
                                  size: 14,
                                  color: colors.danger,
                                )
                              : null,
                          onPressed: () => _cubit.selectDay(i),
                          onOptions: () => _dayMenu(anchor, i),
                          optionsLabel: l10n.programDayActions,
                        ),
                      ),
                    if (state.canAddDay)
                      ForgeChip.add(
                        label: l10n.programAddDay,
                        onPressed: _addDay,
                      ),
                  ],
                ),
                if (daysError != null) danger(daysError),
                if (items.isNotEmpty)
                  Text(
                    l10n.builderDaySummary(
                      l10n.dayName(day, dayIndex),
                      l10n.programDaySummary(
                        items.length,
                        l10n.estimateText(estimateDay(day)),
                      ),
                    ),
                    style: style.data.copyWith(color: colors.inkMuted),
                  ),
                for (final issue in dayIssues) danger(l10n.dayIssueText(issue)),
                if (items.isEmpty && !dayIssues.contains(DayIssue.noItems))
                  EmptyView(
                    icon: ForgeIcons.fitnessCenter,
                    title: l10n.builderDayEmptyTitle,
                    message: l10n.builderDayEmptyBody,
                    compact: true,
                    card: true,
                  ),
              ],
            ),
          ),
        ),
        if (items.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            sliver: BuilderCard(
              sliver: SliverReorderableList(
                itemCount: items.length,
                onReorderItem: _cubit.moveItem,
                // The dragged row is rebuilt in the navigator's overlay,
                // above this page's cubit, which the row reads.
                proxyDecorator: (child, index, _) => BlocProvider.value(
                  value: _cubit,
                  child: _ItemTile(
                    index: index,
                    items: items,
                    state: state,
                    onReplace: () => _replace(index),
                    lifted: true,
                  ),
                ),
                itemBuilder: (context, index) => _ItemTile(
                  key: ObjectKey(items[index]),
                  index: index,
                  items: items,
                  state: state,
                  onReplace: () => _replace(index),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.xl),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.sm,
              children: [
                ForgeAddButton(
                  label: l10n.programAddExercises,
                  onPressed: state.freeSlots > 0
                      ? () => _addExercises(state)
                      : null,
                ),
                if (state.freeSlots == 0)
                  Text(
                    l10n.builderDayFull(ProgramLimits.maxItemsPerDay),
                    textAlign: TextAlign.center,
                    style: text.bodySmall!.copyWith(color: colors.inkMuted),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addExercises(ProgramBuilderState state) async {
    final picked = await context.push<List<Exercise>>(
      widget.picker(max: state.freeSlots, multiple: true),
    );
    if (picked != null && picked.isNotEmpty) _cubit.addExercises(picked);
  }

  /// An exercise no longer in the library is replaced without its
  /// similar ones.
  Future<void> _replace(int index) async {
    final state = _cubit.state;
    final item = state.day?.items.elementAtOrNull(index);
    if (item == null) return;
    final picked = await pickReplacement(
      context,
      exerciseId: state.isUnavailable(item) ? null : item.exerciseId,
      picker: widget.picker,
    );
    if (picked != null) _cubit.replaceExercise(index, picked);
  }
}

/// Names day [number]: its name, or empty for "Day n". Pops with the name,
/// or null when cancelled.
class _RenameDayDialog extends StatefulWidget {
  const _RenameDayDialog({required this.name, required this.number});

  final String name;
  final int number;

  @override
  State<_RenameDayDialog> createState() => _RenameDayDialogState();
}

class _RenameDayDialogState extends State<_RenameDayDialog> {
  late final _controller = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ForgeDialog(
      title: l10n.builderRenameDay,
      message: l10n.builderRenameDayBody,
      field: ForgeTextField(
        label: l10n.programDayName,
        hint: l10n.programDayDefault(widget.number),
        controller: _controller,
        autofocus: true,
        inputFormatters: [maxLengthFormatter(ProgramLimits.maxDayNameLength)],
        textInputAction: TextInputAction.done,
        onSubmitted: (name) => Navigator.pop(context, name),
      ),
      action: ForgeButton(
        label: l10n.programSave,
        onPressed: () => Navigator.pop(context, _controller.text),
      ),
      cancel: ForgeButton(
        label: l10n.cancel,
        variant: ForgeButtonVariant.secondary,
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}

/// An item of the day as a [BuilderRow]: its values as chips, which open
/// the item's editor, and its actions in the ⋯ menu. A superset's rows
/// show the rest only on the last, a circuit's only reps or time, with
/// the group's rest (and a circuit's rounds) in the header above the
/// first. An item whose exercise left the library is the row's
/// unavailable form.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    super.key,
    required this.index,
    required this.items,
    required this.state,
    required this.onReplace,
    this.lifted = false,
  });

  final int index;
  final List<ProgramItem> items;
  final ProgramBuilderState state;
  final VoidCallback onReplace;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProgramBuilderCubit>();
    final item = items[index];
    final exercise = state.exercises[item.exerciseId];
    final (start, end) = groupRange(items, index);
    final grouped = item.group != null;
    final divided = index > 0 && !(grouped && index > start);
    final remove = ForgeMenuItem(
      label: l10n.programRemoveItem,
      icon: ForgeIcons.delete,
      onTap: () => cubit.removeItem(index),
      destructive: true,
    );
    final replace = ForgeMenuItem(
      label: l10n.programReplaceExercise,
      icon: ForgeIcons.sync,
      onTap: onReplace,
    );
    if (state.isUnavailable(item) || exercise == null) {
      return BuilderRow.unavailable(
        index: index,
        name: l10n.programExerciseUnavailable,
        help: l10n.programUnavailableHelp,
        menu: [replace, remove],
        divided: divided,
      );
    }
    final issues = state.validation.itemIssues(state.selectedDay, index);
    final circuit = grouped && end - start > 2;
    final canLink = canLinkWithNext(items, index);
    void edit() => _edit(context, exercise);
    String rest(int seconds) => l10n.restClock(seconds);
    final last = items[end - 1];
    final work = switch (item.durationS) {
      final seconds? => BuilderValue(
        label: l10n.builderRowTime,
        value: l10n.programSeconds(seconds),
        onTap: edit,
      ),
      null => BuilderValue(
        label: l10n.builderRowReps,
        value: l10n.itemReps(item),
        onTap: edit,
      ),
    };
    return BuilderRow(
      index: index,
      name: exercise.localized(context).name,
      values: [
        if (!circuit)
          BuilderValue(
            label: l10n.builderRowSets,
            value: '${item.sets}',
            onTap: edit,
          ),
        work,
        if (!grouped || (!circuit && index == end - 1))
          BuilderValue(
            label: l10n.builderRowRest,
            value: rest(item.restS),
            onTap: edit,
          ),
      ],
      divided: divided,
      grouped: grouped,
      groupHeader: !grouped || index != start
          ? null
          : circuit
          ? l10n.builderRowCircuit(item.sets, rest(last.restS))
          : l10n.builderRowSuperset(rest(last.restS)),
      lifted: lifted,
      onMoveUp: index == 0 ? null : () => cubit.moveItem(index, index - 1),
      onMoveDown: index == items.length - 1
          ? null
          : () => cubit.moveItem(index, index + 1),
      issues: [for (final issue in issues) l10n.itemIssueText(issue)],
      menu: [
        ForgeMenuItem(
          label: l10n.programEditItem,
          icon: ForgeIcons.tune,
          onTap: edit,
        ),
        replace,
        if (canLink)
          ForgeMenuItem(
            label: linkedSize(items, index) == 2
                ? l10n.programMakeSuperset
                : l10n.programMakeCircuit,
            icon: ForgeIcons.dragHandle,
            onTap: () => cubit.linkWithNext(index),
          ),
        if (grouped)
          ForgeMenuItem(
            label: l10n.programUngroup,
            icon: ForgeIcons.remove,
            onTap: () => cubit.ungroup(index),
          ),
        remove,
      ],
    );
  }

  void _edit(BuildContext context, Exercise exercise) {
    final cubit = context.read<ProgramBuilderCubit>();
    final type = exercise.loggingType;
    showForgeBottomSheet<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: ItemTargetsSheet(
          title: exercise.localized(context).name,
          durationBased: type.isDurationBased,
          logsWeight: type.logsWeight,
          targets: _BuilderItemTargets(cubit, index),
        ),
      ),
    );
  }
}

/// The builder's item at [index] of the selected day.
class _BuilderItemTargets implements ItemTargets {
  const _BuilderItemTargets(this._cubit, this._index);

  final ProgramBuilderCubit _cubit;
  final int _index;

  @override
  ProgramItem get item => _cubit.state.day!.items[_index];

  @override
  WeightUnit get weightUnit => _cubit.weightUnit;

  @override
  Set<ItemIssue> watchIssues(BuildContext context) => context.select(
    (ProgramBuilderCubit cubit) => cubit.state.liveItemIssues(_index),
  );

  @override
  void setSets(String text) => _cubit.setSets(_index, text);

  @override
  void setRepMin(String text) => _cubit.setRepMin(_index, text);

  @override
  void setRepMax(String text) => _cubit.setRepMax(_index, text);

  @override
  void setDuration(String text) => _cubit.setDuration(_index, text);

  @override
  void setRest(int seconds) => _cubit.setRest(_index, '$seconds');

  @override
  void setTarget(String text) => _cubit.setTarget(_index, text);
}
