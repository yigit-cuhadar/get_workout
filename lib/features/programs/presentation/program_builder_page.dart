import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/max_length_formatter.dart';
import '../../../core/unsaved_changes.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/program.dart';
import '../../../core/grouping.dart';
import '../domain/program_editing.dart';
import '../domain/program_validation.dart';
import 'program_builder_cubit.dart';
import 'program_text.dart';

/// Creates a program, or edits program [programId].
class ProgramBuilderPage extends StatelessWidget {
  const ProgramBuilderPage({super.key, this.programId});

  final String? programId;

  @override
  Widget build(BuildContext context) {
    final unit = context.read<SettingsCubit>().state.settings.weightUnit;
    return BlocProvider(
      create: (_) => sl<ProgramBuilderCubit>(param1: programId, param2: unit),
      child: const _BuilderView(),
    );
  }
}

class _BuilderView extends StatelessWidget {
  const _BuilderView();

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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.programAdjusted(l10n.inlineList(names))),
              ),
            );
            cubit.adjustedShown();
            return;
          }
          switch (state.status) {
            case ProgramBuilderStatus.saved when cubit.isEditing:
              context.pop();
            case ProgramBuilderStatus.saved:
              context.go(Routes.program(state.savedId!, created: true));
            case ProgramBuilderStatus.closed:
              context.go(Routes.programs);
            case ProgramBuilderStatus.saveFailed:
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    state.failure is NetworkFailure
                        ? l10n.errorNetwork
                        : l10n.programSaveFailed,
                  ),
                ),
              );
            default:
          }
        },
        builder: (context, state) {
          final catalogue = context.watch<ExerciseCatalogueCubit>().state;
          final ready =
              state.status != ProgramBuilderStatus.loading &&
              catalogue is CatalogueReady;
          return PopScope(
            canPop: !state.dirty,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              if (await UnsavedChangesGuard.ask(context) && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Scaffold(
              appBar: AppBar(
                title: Text(
                  cubit.isEditing ? l10n.programEditTitle : l10n.programNew,
                ),
                actions: [
                  if (ready)
                    TextButton(
                      onPressed: state.isBusy ? null : cubit.save,
                      child: Text(l10n.programSave),
                    ),
                ],
              ),
              body: switch (state.status) {
                ProgramBuilderStatus.notFound => EmptyView(
                  message: l10n.programNotFound,
                ),
                ProgramBuilderStatus.loadFailed => ErrorView(
                  message: l10n.programsLoadFailed,
                  retryLabel: l10n.retry,
                  onRetry: cubit.load,
                ),
                _ => switch (catalogue) {
                  CatalogueFailed() => ErrorView(
                    message: l10n.libraryLoadFailed,
                    retryLabel: l10n.retry,
                    onRetry: context.read<ExerciseCatalogueCubit>().retry,
                  ),
                  _ when !ready => const LoadingView(),
                  _ => const _Form(),
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
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.programDiscardTitle),
        content: Text(l10n.programDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.programKeepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.programDiscard),
          ),
        ],
      ),
    );
    return discard == true;
  }
}

/// The program's fields and days, then the selected day's items, which
/// reorder by dragging.
class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final ProgramBuilderCubit _cubit = context.read<ProgramBuilderCubit>();
  late final _name = TextEditingController(text: _cubit.state.program.name);
  late final _weeks = TextEditingController(
    text: _cubit.state.program.lengthWeeks?.toString() ?? '',
  );

  /// The name field of the day last added, which takes the focus once;
  /// opening the builder or switching days never does. A fresh node per
  /// added day: moving a focused node to the next field would leave it
  /// focused without a keyboard.
  FocusNode? _newDayName;
  Key? _newDayKey;

  @override
  void dispose() {
    _name.dispose();
    _weeks.dispose();
    _newDayName?.dispose();
    super.dispose();
  }

  /// A new field per day, so it shows that day's name.
  static Key _dayKey(ProgramBuilderState state) =>
      ValueKey('day-${state.selectedDay}-${state.program.days.length}');

  void _addDay() {
    final days = _cubit.state.program.days.length;
    _cubit.addDay();
    if (_cubit.state.program.days.length == days) return;
    final previous = _newDayName;
    final node = _newDayName = FocusNode();
    _newDayKey = _dayKey(_cubit.state);
    // The new day's field is built, and the previous one's gone, by then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previous?.dispose();
      if (mounted) node.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ProgramBuilderCubit>().state;
    final validation = state.validation;
    final day = state.day!;
    final dayIndex = state.selectedDay;
    final dayKey = _dayKey(state);
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
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: Gap.xl),
      // The dragged row is rebuilt in the navigator's overlay, above this
      // page's cubit, which the row reads.
      proxyDecorator: (child, _, _) => BlocProvider.value(
        value: _cubit,
        child: Material(elevation: 4, child: child),
      ),
      header: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [
                maxLengthFormatter(ProgramLimits.maxNameLength),
              ],
              decoration: InputDecoration(
                labelText: l10n.programName,
                errorText: programError({
                  ProgramIssue.nameMissing,
                  ProgramIssue.nameTooLong,
                }),
              ),
              onChanged: _cubit.setName,
            ),
            const SizedBox(height: Gap.sm),
            TextField(
              controller: _weeks,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              decoration: InputDecoration(
                labelText: l10n.programLength,
                helperText: l10n.programLengthHelp,
                errorText: programError({ProgramIssue.lengthWeeksOutOfRange}),
              ),
              onChanged: _cubit.setLengthWeeks,
            ),
            const SizedBox(height: Gap.md),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.xs,
              children: [
                for (final (i, other) in state.program.days.indexed)
                  ChoiceChip(
                    label: Text(l10n.dayName(other, i)),
                    selected: i == dayIndex,
                    avatar:
                        validation.dayIssues(i).isNotEmpty ||
                            validation.items.keys.any((ref) => ref.day == i)
                        ? Icon(
                            Icons.error_outline,
                            color: Theme.of(context).colorScheme.error,
                          )
                        : null,
                    onSelected: (_) => _cubit.selectDay(i),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add),
                  label: Text(l10n.programAddDay),
                  onPressed: state.canAddDay ? _addDay : null,
                ),
              ],
            ),
            if (daysError != null) _ErrorText(daysError),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: dayKey,
                    focusNode: dayKey == _newDayKey ? _newDayName : null,
                    initialValue: day.name,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: [
                      maxLengthFormatter(ProgramLimits.maxDayNameLength),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.programDayName,
                      hintText: l10n.programDayDefault(dayIndex + 1),
                      helperText: day.items.isEmpty
                          ? null
                          : l10n.estimateText(estimateDay(day)),
                      errorText: dayIssues.contains(DayIssue.nameTooLong)
                          ? l10n.dayIssueText(DayIssue.nameTooLong)
                          : null,
                    ),
                    onChanged: (name) => _cubit.renameDay(dayIndex, name),
                  ),
                ),
                _DayMenu(index: dayIndex, count: state.program.days.length),
              ],
            ),
            for (final issue in dayIssues)
              if (issue != DayIssue.nameTooLong)
                _ErrorText(l10n.dayIssueText(issue)),
          ],
        ),
      ),
      footer: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: Text(l10n.programAddExercises),
          onPressed: state.freeSlots > 0 ? () => _addExercises(state) : null,
        ),
      ),
      itemCount: items.length,
      onReorderItem: _cubit.moveItem,
      itemBuilder: (context, index) => _ItemTile(
        key: ObjectKey(items[index]),
        index: index,
        items: items,
        state: state,
        onReplace: () => _replace(index),
      ),
    );
  }

  Future<void> _addExercises(ProgramBuilderState state) async {
    final picked = await context.push<List<Exercise>>(
      Routes.exercisePicker(max: state.freeSlots, multiple: true),
    );
    if (picked != null && picked.isNotEmpty) _cubit.addExercises(picked);
  }

  Future<void> _replace(int index) async {
    final picked = await context.push<List<Exercise>>(
      Routes.exercisePicker(max: 1, multiple: false),
    );
    if (picked != null && picked.isNotEmpty) {
      _cubit.replaceExercise(index, picked.single);
    }
  }
}

class _DayMenu extends StatelessWidget {
  const _DayMenu({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProgramBuilderCubit>();
    return PopupMenuButton<VoidCallback>(
      tooltip: l10n.programDayActions,
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: index > 0,
          value: () => cubit.moveDay(index, index - 1),
          child: Text(l10n.programMoveDayEarlier),
        ),
        PopupMenuItem(
          enabled: index < count - 1,
          value: () => cubit.moveDay(index, index + 1),
          child: Text(l10n.programMoveDayLater),
        ),
        PopupMenuItem(
          enabled: count > 1,
          value: () => _delete(context),
          child: Text(l10n.programDeleteDay),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProgramBuilderCubit>();
    if (cubit.state.program.days[index].items.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.programDeleteDayTitle),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.programDeleteDay),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    cubit.deleteDay(index);
  }
}

enum _ItemAction { edit, replace, link, ungroup, remove }

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    super.key,
    required this.index,
    required this.items,
    required this.state,
    required this.onReplace,
  });

  final int index;
  final List<ProgramItem> items;
  final ProgramBuilderState state;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<ProgramBuilderCubit>();
    final item = items[index];
    final exercise = state.exercises[item.exerciseId];
    final unavailable = state.isUnavailable(item);
    final issues = state.validation.itemIssues(state.selectedDay, index);
    final group = item.group;
    final (start, end) = groupRange(items, index);
    final canLink = canLinkWithNext(items, index);
    return ListTile(
      leading: ReorderableDragStartListener(
        index: index,
        child: Icon(Icons.drag_handle, semanticLabel: l10n.programReorder),
      ),
      title: Text(
        exercise == null
            ? l10n.programExerciseUnavailable
            : exercise.localized(context).name,
        style: unavailable ? TextStyle(color: theme.colorScheme.error) : null,
      ),
      subtitle: Text(
        [
          [
            l10n.itemSummary(item, cubit.weightUnit),
            l10n.programRest(item.restS),
            if (group != null) l10n.groupLabel(group, end - start),
          ].join(' · '),
          for (final issue in issues)
            if (issue != ItemIssue.exerciseUnavailable)
              l10n.itemIssueText(issue),
          if (unavailable) l10n.programUnavailableHelp,
        ].join('\n'),
      ),
      isThreeLine: issues.isNotEmpty || unavailable,
      onTap: unavailable ? onReplace : () => _edit(context),
      trailing: PopupMenuButton<_ItemAction>(
        tooltip: l10n.programItemActions,
        onSelected: (action) => switch (action) {
          _ItemAction.edit => _edit(context),
          _ItemAction.replace => onReplace(),
          _ItemAction.link => cubit.linkWithNext(index),
          _ItemAction.ungroup => cubit.ungroup(index),
          _ItemAction.remove => cubit.removeItem(index),
        },
        itemBuilder: (_) => [
          if (!unavailable)
            PopupMenuItem(
              value: _ItemAction.edit,
              child: Text(l10n.programEditItem),
            ),
          PopupMenuItem(
            value: _ItemAction.replace,
            child: Text(l10n.programReplaceExercise),
          ),
          if (canLink)
            PopupMenuItem(
              value: _ItemAction.link,
              child: Text(
                linkedSize(items, index) == 2
                    ? l10n.programMakeSuperset
                    : l10n.programMakeCircuit,
              ),
            ),
          if (group != null)
            PopupMenuItem(
              value: _ItemAction.ungroup,
              child: Text(l10n.programUngroup),
            ),
          PopupMenuItem(
            value: _ItemAction.remove,
            child: Text(l10n.programRemoveItem),
          ),
        ],
      ),
    );
  }

  void _edit(BuildContext context) {
    final cubit = context.read<ProgramBuilderCubit>();
    final type = state.exercises[items[index].exerciseId]?.loggingType;
    if (type == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: _ItemEditor(
          index: index,
          durationBased: type.isDurationBased,
          logsWeight: type.logsWeight,
        ),
      ),
    );
  }
}

/// Sets, reps or duration, rest and target of one item; every change
/// applies at once.
class _ItemEditor extends StatefulWidget {
  const _ItemEditor({
    required this.index,
    required this.durationBased,
    required this.logsWeight,
  });

  final int index;
  final bool durationBased;
  final bool logsWeight;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final ProgramBuilderCubit _cubit = context.read<ProgramBuilderCubit>();
  late final ProgramItem _item = _cubit.state.day!.items[widget.index];
  late final _sets = _controller('${_item.sets}');
  late final _repMin = _controller(_item.repMin?.toString() ?? '');
  late final _repMax = _controller(_item.repMax?.toString() ?? '');
  late final _duration = _controller(_item.durationS?.toString() ?? '');
  late final _rest = _controller('${_item.restS}');
  late final _target = _controller(_targetText());
  final _controllers = <TextEditingController>[];

  TextEditingController _controller(String text) {
    final controller = TextEditingController(text: text);
    _controllers.add(controller);
    return controller;
  }

  String _targetText() {
    final kg = _item.targetKg;
    if (kg == null) return '';
    final value = _cubit.weightUnit.fromKg(kg);
    final fixed = value.toStringAsFixed(2);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final issues = context.select(
      (ProgramBuilderCubit cubit) => cubit.state.liveItemIssues(widget.index),
    );
    final index = widget.index;
    String? error(Set<ItemIssue> of) =>
        issues.where(of.contains).map(l10n.itemIssueText).firstOrNull;
    final repsError = error({
      ItemIssue.repsMissing,
      ItemIssue.repsOutOfRange,
      ItemIssue.repRangeInverted,
    });
    return Padding(
      padding: EdgeInsets.only(
        left: Gap.md,
        right: Gap.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Gap.md,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NumberField(
              controller: _sets,
              label: l10n.programSets,
              error: error({ItemIssue.setsOutOfRange}),
              onChanged: (text) => _cubit.setSets(index, text),
            ),
            if (widget.durationBased)
              _NumberField(
                controller: _duration,
                label: l10n.programDurationSeconds,
                error: error({
                  ItemIssue.durationMissing,
                  ItemIssue.durationOutOfRange,
                }),
                onChanged: (text) => _cubit.setDuration(index, text),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _NumberField(
                      controller: _repMin,
                      label: l10n.programRepMin,
                      error: repsError,
                      onChanged: (text) => _cubit.setRepMin(index, text),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: _NumberField(
                      controller: _repMax,
                      label: l10n.programRepMax,
                      error: repsError == null ? null : '',
                      onChanged: (text) => _cubit.setRepMax(index, text),
                    ),
                  ),
                ],
              ),
            _NumberField(
              controller: _rest,
              label: l10n.programRestSeconds,
              error: error({ItemIssue.restOutOfRange}),
              onChanged: (text) => _cubit.setRest(index, text),
            ),
            if (widget.logsWeight)
              _NumberField(
                controller: _target,
                label: l10n.programTarget(
                  l10n.weightUnitLabel(_cubit.weightUnit),
                ),
                error: error({ItemIssue.targetOutOfRange}),
                decimal: true,
                onChanged: (text) => _cubit.setTarget(index, text),
              ),
            if (error({ItemIssue.wrongTarget}) case final text?)
              _ErrorText(text),
            const SizedBox(height: Gap.md),
            ForgeButton(
              label: l10n.libraryDone,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.error,
    required this.onChanged,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String label;
  final String? error;
  final ValueChanged<String> onChanged;
  final bool decimal;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.sm),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        decimal
            ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            : FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(decimal ? 7 : 4),
      ],
      decoration: InputDecoration(labelText: label, errorText: error),
      onChanged: onChanged,
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}
