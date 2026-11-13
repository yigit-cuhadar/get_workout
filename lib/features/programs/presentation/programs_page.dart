import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../generator/presentation/generator_entry.dart';
import '../../settings/presentation/first_weekday.dart';
import '../../workout/presentation/start_workout.dart';
import '../domain/program.dart';
import '../domain/program_schedule.dart';
import 'missed_day_prompt.dart';
import 'program_list_cubit.dart';
import 'program_text.dart';

/// The Programs tab's first page: the active program's card with the next
/// workout and this week's days, then the ways into the ready-made
/// programs, the generator and the builder and an empty workout, then the
/// other programs.
class ProgramsPage extends StatelessWidget {
  const ProgramsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<ProgramListCubit>(),
    child: Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).tabPrograms)),
      body: const _ProgramsView(),
    ),
  );
}

class _ProgramsView extends StatefulWidget {
  const _ProgramsView();

  @override
  State<_ProgramsView> createState() => _ProgramsViewState();
}

class _ProgramsViewState extends State<_ProgramsView> {
  late final ProgramListCubit _cubit = context.read<ProgramListCubit>();
  late final AppLifecycleListener _lifecycle;

  /// The plan's today moves on while the page is away or the app sleeps,
  /// without a new snapshot to recompute it.
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _cubit.refreshNow);
    _cubit.refreshNow();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A refused write is told by the shell's ProgramWritesNotice, a failed
    // missed-day choice by its prompt.
    return BlocBuilder<ProgramListCubit, ProgramListState>(
      builder: (context, state) => switch (state.status) {
        ProgramListStatus.loading => const LoadingView(),
        ProgramListStatus.failure => ErrorView(
          message: l10n.programsLoadFailed,
          retryLabel: l10n.retry,
          onRetry: _cubit.retry,
        ),
        ProgramListStatus.ready => _Programs(state),
      },
    );
  }
}

class _Programs extends StatelessWidget {
  const _Programs(this.state);
  final ProgramListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final others = state.otherPrograms;
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        if (state.activeProgram != null) ...[
          _ActiveProgramCard(state),
          const SizedBox(height: Gap.md),
        ],
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(l10n.catalogueTitle),
                subtitle: Text(l10n.catalogueEntryInfo),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(Routes.catalogue),
              ),
              const GeneratorEntry(),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(l10n.programNew),
                subtitle: Text(l10n.programNewInfo),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(Routes.programNew),
              ),
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: Text(l10n.workoutStartEmpty),
                onTap: () => startFreeWorkout(context),
              ),
            ],
          ),
        ),
        if (state.programs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Gap.md),
            child: Text(l10n.programsEmpty),
          ),
        if (others.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, Gap.lg, 0, Gap.sm),
            child: Text(
              state.activeProgram == null
                  ? l10n.programsMine
                  : l10n.programsOther,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final program in others)
                  _ProgramTile(
                    program,
                    locked: state.access(program) == ProgramAccess.locked,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The active program: its name, which opens it, where it stands, the next
/// workout with the one Start of a program day here, a missed day's prompt
/// and this week's days with their state.
class _ActiveProgramCard extends StatelessWidget {
  const _ActiveProgramCard(this.state);
  final ProgramListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final program = state.activeProgram!;
    final access = state.access(program);
    final weeks = program.lengthWeeks;
    final week = state.week;
    final progress = state.finished
        ? l10n.programFinished
        : [
            if (week != null)
              weeks == null
                  ? l10n.programWeekNumber(week)
                  : l10n.programWeekOf(week, weeks),
            l10n.weekdayList(
              state.active!.weekdays,
              context.watchFirstWeekday(),
            ),
          ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.programActive,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(program.name, style: theme.textTheme.titleMedium),
              ],
            ),
            subtitle: Text(progress),
            trailing: access == ProgramAccess.locked
                ? Icon(
                    Icons.lock_outline,
                    semanticLabel: l10n.catalogueLockedLabel,
                  )
                : const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.program(program.id!)),
          ),
          if (!state.finished && weeks != null && week != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: LinearProgressIndicator(value: week / weeks),
            ),
          // Locked, it opens the paywall instead.
          if (state.nextDayIndex case final day?)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 0),
              child: ForgeButton(
                label: l10n.workoutStartDay(
                  l10n.dayName(program.days[day], day),
                ),
                onPressed: () => startProgramDay(context, program, day),
              ),
            ),
          // Kept, not stopped: it carries on once premium is back.
          if (access == ProgramAccess.locked)
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline),
                  const SizedBox(width: Gap.sm),
                  Expanded(child: Text(l10n.programLockedActive)),
                ],
              ),
            )
          else if (access == ProgramAccess.waiting)
            const Padding(padding: EdgeInsets.all(Gap.md), child: LoadingView())
          else ...[
            if (state.missed case final missed?)
              MissedDayPrompt(
                program: program,
                missed: missed,
                moveDate: state.moveDate!,
                busy: state.resolving,
              ),
            if (!state.finished) ...[
              const SizedBox(height: Gap.sm),
              _WeekPlan(state),
            ],
            const SizedBox(height: Gap.sm),
          ],
        ],
      ),
    );
  }
}

class _ProgramTile extends StatelessWidget {
  const _ProgramTile(this.program, {required this.locked});

  final Program program;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final weeks = program.lengthWeeks;
    return ListTile(
      title: Text(program.name),
      subtitle: Text(
        [
          l10n.programDayCount(program.days.length),
          if (weeks != null) l10n.programWeekCount(weeks),
        ].join(' · '),
      ),
      trailing: locked
          ? Icon(Icons.lock_outline, semanticLabel: l10n.catalogueLockedLabel)
          : const Icon(Icons.chevron_right),
      onTap: () => context.go(Routes.program(program.id!)),
    );
  }
}

/// This week's planned and done days of the active program, each with its
/// state; none starts, the next workout above does.
class _WeekPlan extends StatelessWidget {
  const _WeekPlan(this.state);
  final ProgramListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final program = state.activeProgram!;
    final plan = state.weekPlan;
    if (plan.isEmpty) {
      return ListTile(dense: true, title: Text(l10n.programWeekEmpty));
    }
    bool isNext(PlannedDay day) =>
        day.status == PlannedStatus.planned &&
        day.dayIndex == state.nextDayIndex &&
        day.date == state.nextDate;
    return Column(
      children: [
        for (final day in plan)
          ListTile(
            dense: true,
            title: Text(
              day.dayIndex < program.days.length
                  ? l10n.dayName(program.days[day.dayIndex], day.dayIndex)
                  : l10n.programDayDefault(day.dayIndex + 1),
            ),
            subtitle: Text(l10n.planDate(day.date)),
            trailing: switch (day.status) {
              PlannedStatus.done => Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
                semanticLabel: l10n.programDayDone,
              ),
              PlannedStatus.missed => Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
                semanticLabel: l10n.programDayMissed,
              ),
              PlannedStatus.planned when isNext(day) => Text(
                l10n.programDayNext,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              PlannedStatus.planned => Icon(
                Icons.schedule,
                semanticLabel: l10n.programDayPlanned,
              ),
            },
          ),
      ],
    );
  }
}
