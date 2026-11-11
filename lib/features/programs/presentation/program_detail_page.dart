import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../workout/presentation/start_workout.dart';
import '../domain/program.dart';
import '../../../core/grouping.dart';
import '../domain/program_editing.dart';
import '../domain/program_schedule.dart';
import 'program_detail_cubit.dart';
import 'program_list_cubit.dart';
import 'program_text.dart';
import 'weekday_dialog.dart';

/// One program: its days and exercises, and starting, stopping, editing,
/// duplicating and deleting it. Taken from the shared list, so it opens at
/// once from the list and also works from a bare link.
class ProgramDetailPage extends StatefulWidget {
  const ProgramDetailPage({super.key, required this.id, this.created = false});

  final String id;

  /// The program was just stored: the list may not show it yet, so the page
  /// waits for it, for up to [createdWait], before saying it does not exist.
  final bool created;

  static const createdWait = Duration(seconds: 3);

  @override
  State<ProgramDetailPage> createState() => _ProgramDetailPageState();
}

class _ProgramDetailPageState extends State<ProgramDetailPage> {
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (widget.created) {
      _wait = Timer(ProgramDetailPage.createdWait, () => setState(() {}));
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  bool get _waiting => _wait?.isActive ?? false;

  String get id => widget.id;

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<ProgramListCubit>(),
    child: BlocBuilder<ProgramListCubit, ProgramListState>(
      // Once shown, the page keeps its program; a delete removing it from
      // the list must not swap the page out while it closes.
      buildWhen: (previous, current) =>
          previous.program(id) == null || current.program(id) != null,
      builder: (context, state) {
        final program = state.program(id);
        if (program != null) {
          return BlocProvider(
            create: (_) => sl<ProgramDetailCubit>(param1: id),
            child: _ProgramDetailView(program: program, list: state),
          );
        }
        final l10n = AppLocalizations.of(context);
        return Scaffold(
          appBar: AppBar(),
          body: switch (state.status) {
            ProgramListStatus.loading => const LoadingView(),
            ProgramListStatus.failure => ErrorView(
              message: l10n.programsLoadFailed,
              retryLabel: l10n.retry,
              onRetry: context.read<ProgramListCubit>().retry,
            ),
            ProgramListStatus.ready when _waiting => const LoadingView(),
            ProgramListStatus.ready => EmptyView(message: l10n.programNotFound),
          },
        );
      },
    ),
  );
}

class _ProgramDetailView extends StatelessWidget {
  const _ProgramDetailView({required this.program, required this.list});

  final Program program;
  final ProgramListState list;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProgramDetailCubit>();
    final active = list.active?.programId == program.id ? list.active : null;
    return BlocConsumer<ProgramDetailCubit, ProgramDetailState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        switch (state.status) {
          case ProgramDetailStatus.deleted || ProgramDetailStatus.closed:
            context.go(Routes.programs);
          case ProgramDetailStatus.duplicated:
            context.go(Routes.program(state.copyId!, created: true));
          case ProgramDetailStatus.failed:
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.failure is NetworkFailure
                      ? l10n.errorNetwork
                      : l10n.programActionFailed,
                ),
              ),
            );
          default:
        }
      },
      builder: (context, state) {
        final busy = state.isBusy;
        return Scaffold(
          appBar: AppBar(
            title: Text(program.name),
            actions: [
              IconButton(
                tooltip: l10n.programEdit,
                icon: const Icon(Icons.edit_outlined),
                onPressed: busy
                    ? null
                    : () => context.go(Routes.programEdit(program.id!)),
              ),
              PopupMenuButton<VoidCallback>(
                enabled: !busy,
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: () => cubit.duplicate(l10n.programCopyName),
                    child: Text(l10n.programDuplicate),
                  ),
                  PopupMenuItem(
                    value: () => _delete(context, active != null),
                    child: Text(l10n.programDelete),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: Gap.md),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: active == null
                    ? ForgeButton(
                        label: l10n.programStart,
                        loading: busy,
                        onPressed: () => _start(context),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.programActiveOn(
                              l10n.weekdayList(active.weekdays),
                            ),
                          ),
                          if (active.weekdays.length != program.days.length)
                            Text(
                              l10n.programDaysMismatch(program.days.length),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          const SizedBox(height: Gap.sm),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => _changeWeekdays(
                                          context,
                                          active.weekdays,
                                        ),
                                  child: Text(l10n.programChangeDays),
                                ),
                              ),
                              const SizedBox(width: Gap.sm),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy ? null : cubit.stop,
                                  child: Text(l10n.programStop),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              if (program.lengthWeeks case final weeks?)
                ListTile(title: Text(l10n.programWeekCount(weeks))),
              for (final (index, day) in program.days.indexed)
                _DaySection(program: program, day: day, index: index),
            ],
          ),
        );
      },
    );
  }

  Future<void> _start(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProgramDetailCubit>();
    final current = list.activeProgram;
    if (current != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.programReplaceTitle),
          content: Text(l10n.programReplaceBody(current.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.programReplace),
            ),
          ],
        ),
      );
      if (replace != true || !context.mounted) return;
    }
    final weekdays = await showWeekdayDialog(
      context,
      count: program.days.length,
      initial: ProgramSchedule.suggestedWeekdays(program.days.length),
      confirmLabel: l10n.programStart,
    );
    if (weekdays != null) await cubit.start(weekdays);
  }

  Future<void> _changeWeekdays(BuildContext context, List<int> current) async {
    final cubit = context.read<ProgramDetailCubit>();
    final count = program.days.length;
    final weekdays = await showWeekdayDialog(
      context,
      count: count,
      initial: current.length == count
          ? current
          : ProgramSchedule.suggestedWeekdays(count),
      confirmLabel: AppLocalizations.of(context).programSave,
    );
    if (weekdays != null) await cubit.changeWeekdays(weekdays);
  }

  Future<void> _delete(BuildContext context, bool isActive) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProgramDetailCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.programDeleteTitle),
        content: Text(
          isActive ? l10n.programDeleteActiveBody : l10n.programDeleteBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.programDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) await cubit.delete();
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.program,
    required this.day,
    required this.index,
  });

  final Program program;
  final ProgramDay day;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final catalogue = context.select(
      (ExerciseCatalogueCubit cubit) => cubit.state,
    );
    final exercises = catalogue is CatalogueReady
        ? {for (final e in catalogue.exercises) e.id: e}
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        ListTile(
          title: Text(
            l10n.dayName(day, index),
            style: theme.textTheme.titleMedium,
          ),
          subtitle: day.items.isEmpty
              ? null
              : Text(l10n.estimateText(estimateDay(day))),
          trailing: day.items.isEmpty
              ? null
              : IconButton(
                  tooltip: l10n.workoutStartThisDay,
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () => startProgramDay(context, program, index),
                ),
        ),
        for (final (i, item) in day.items.indexed)
          ListTile(
            dense: true,
            leading: item.group == null ? null : Text(item.group!),
            title: Text(_name(l10n, exercises, item, context)),
            subtitle: Text(
              [
                l10n.itemSummary(item, unit),
                l10n.programRest(item.restS),
                if (item.group case final group?)
                  l10n.groupLabel(group, groupSize(day.items, i)),
              ].join(' · '),
            ),
          ),
      ],
    );
  }

  static int groupSize(List<ProgramItem> items, int index) {
    final (start, end) = groupRange(items, index);
    return end - start;
  }

  static String _name(
    AppLocalizations l10n,
    Map<String, Exercise>? exercises,
    ProgramItem item,
    BuildContext context,
  ) {
    if (exercises == null) return l10n.programExerciseLoading;
    final exercise = exercises[item.exerciseId];
    return exercise == null
        ? l10n.programExerciseUnavailable
        : exercise.localized(context).name;
  }
}
