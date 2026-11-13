import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/first_weekday.dart';
import '../../workout/presentation/start_workout.dart';
import '../domain/active_program.dart';
import '../domain/program.dart';
import '../domain/program_editing.dart';
import '../domain/program_schedule.dart';
import 'program_detail_cubit.dart';
import 'premium_prompt.dart';
import 'program_day_section.dart';
import 'program_list_cubit.dart';
import 'program_text.dart';
import 'weekday_dialog.dart';

/// One program: a summary card with its state, length and weekdays and
/// starting, rescheduling or stopping it, then its days, which open to their
/// exercises and start any day; editing, duplicating and deleting it in the
/// app bar. Taken from the shared list, so it opens at
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
            child: _ProgramDetailView(
              program: program,
              list: state,
              premium: sl<PremiumPrompt>(),
            ),
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
  const _ProgramDetailView({
    required this.program,
    required this.list,
    required this.premium,
  });

  final Program program;
  final ProgramListState list;
  final PremiumPrompt premium;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProgramDetailCubit>();
    final active = list.active?.programId == program.id ? list.active : null;
    final access = list.access(program);
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
            padding: const EdgeInsets.all(Gap.md),
            children: [
              _Summary(
                program: program,
                active: active,
                finished: active != null && list.finished,
                access: access,
                busy: busy,
                premium: premium,
                onStart: () => _start(context),
                onChangeDays: () => _changeWeekdays(context, active!.weekdays),
              ),
              const SizedBox(height: Gap.md),
              _Days(
                program: program,
                // Where the user is in the program; the start of one not
                // running.
                open: active == null ? 0 : list.nextDayIndex,
              ),
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

/// Where the program stands and what can be done with it: its state, its
/// length and days, the weekdays it runs on while active, then Start, or
/// Change days and Stop, or why it is locked.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.program,
    required this.active,
    required this.finished,
    required this.access,
    required this.busy,
    required this.premium,
    required this.onStart,
    required this.onChangeDays,
  });

  final Program program;

  /// Its schedule, when it is the active program.
  final ActiveProgram? active;
  final bool finished;
  final ProgramAccess access;
  final bool busy;
  final PremiumPrompt premium;
  final VoidCallback onStart;
  final VoidCallback onChangeDays;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<ProgramDetailCubit>();
    final active = this.active;
    final weeks = program.lengthWeeks;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    active == null
                        ? l10n.programStateInactive
                        : finished
                        ? l10n.programFinished
                        : l10n.programStateActive,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  [
                    if (weeks != null) l10n.programWeekCount(weeks),
                    l10n.programDayCount(program.days.length),
                  ].join(' · '),
                ),
              ],
            ),
            if (active != null) ...[
              const SizedBox(height: Gap.xs),
              Text(
                l10n.weekdayList(active.weekdays, context.watchFirstWeekday()),
              ),
              if (!finished && active.weekdays.length != program.days.length)
                Text(
                  l10n.programDaysMismatch(program.days.length),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
            ],
            const SizedBox(height: Gap.md),
            if (active == null && access == ProgramAccess.locked)
              PremiumLock(message: l10n.programLockedStart, prompt: premium)
            else if (active == null)
              ForgeButton(
                label: l10n.programStart,
                loading: busy || access == ProgramAccess.waiting,
                onPressed: onStart,
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy || access != ProgramAccess.open
                          ? null
                          : onChangeDays,
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
              if (access == ProgramAccess.locked) ...[
                const SizedBox(height: Gap.sm),
                PremiumLock(message: l10n.programLockedActive, prompt: premium),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The program's days as cards that open to their exercises; any day with
/// exercises starts from its card. Which are open is this page's own view
/// state: the [open] day at first, again once the days change (an edit may
/// have moved them), and added when [open] moves on, e.g. once the program
/// starts.
class _Days extends StatefulWidget {
  const _Days({required this.program, required this.open});

  final Program program;
  final int? open;

  @override
  State<_Days> createState() => _DaysState();
}

class _DaysState extends State<_Days> {
  late var _open = {?widget.open};

  @override
  void didUpdateWidget(_Days oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.program.days, widget.program.days)) {
      _open = {?widget.open};
    } else if (widget.open case final open? when open != oldWidget.open) {
      _open.add(open);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final program = widget.program;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, day) in program.days.indexed) ...[
          if (index > 0) const SizedBox(height: Gap.sm),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  title: Text(
                    l10n.dayName(day, index),
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: day.items.isEmpty
                      ? null
                      : Text(
                          l10n.programDaySummary(
                            day.items.length,
                            l10n.estimateText(estimateDay(day)),
                          ),
                        ),
                  trailing: day.items.isEmpty
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Locked, it opens the paywall instead.
                            IconButton(
                              tooltip: l10n.workoutStartThisDay,
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () =>
                                  startProgramDay(context, program, index),
                            ),
                            IconButton(
                              tooltip: _open.contains(index)
                                  ? l10n.programDayHide
                                  : l10n.programDayShow,
                              icon: Icon(
                                _open.contains(index)
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                              ),
                              onPressed: () => _toggle(index),
                            ),
                          ],
                        ),
                  onTap: day.items.isEmpty ? null : () => _toggle(index),
                ),
                if (_open.contains(index)) ProgramDayItems(day: day),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _toggle(int index) => setState(() {
    if (!_open.remove(index)) _open.add(index);
  });
}
