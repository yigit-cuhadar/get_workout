import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../generator/presentation/generator_entry.dart';
import '../../workout/presentation/start_workout.dart';
import '../domain/program.dart';
import '../domain/program_schedule.dart';
import 'missed_day_prompt.dart';
import 'program_list_cubit.dart';
import 'program_text.dart';

/// Train's "My program" view: the active program with this week's plan,
/// then the ways into the ready-made programs, the generator and the
/// builder and an empty workout, then the other programs. The page around
/// it gives the app bar.
class ProgramsPage extends StatelessWidget {
  const ProgramsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<ProgramListCubit>(),
    child: const _ProgramsView(),
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
    final active = state.activeProgram;
    final others = state.otherPrograms;
    final access = active == null ? null : state.access(active);
    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.md),
      children: [
        if (active != null) ...[
          _Header(l10n.programActive),
          _ProgramTile(
            active,
            locked: access == ProgramAccess.locked,
            subtitle: state.finished
                ? l10n.programFinished
                : l10n.weekdayList(state.active!.weekdays),
          ),
          // Locked, it opens the paywall instead.
          if (state.nextDayIndex case final day?)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: Gap.sm,
              ),
              child: ForgeButton(
                label: l10n.workoutStartDay(
                  l10n.dayName(active.days[day], day),
                ),
                onPressed: () => startProgramDay(context, active, day),
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
                program: active,
                missed: missed,
                moveDate: state.moveDate!,
                busy: state.resolving,
              ),
            if (!state.finished)
              _WeekPlan(program: active, plan: state.weekPlan),
          ],
        ],
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
        if (state.programs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Text(l10n.programsEmpty),
          ),
        if (others.isNotEmpty) ...[
          _Header(active == null ? l10n.programsMine : l10n.programsOther),
          for (final program in others)
            _ProgramTile(
              program,
              locked: state.access(program) == ProgramAccess.locked,
            ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _ProgramTile extends StatelessWidget {
  const _ProgramTile(this.program, {required this.locked, this.subtitle});

  final Program program;
  final bool locked;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final weeks = program.lengthWeeks;
    final details = [
      l10n.programDayCount(program.days.length),
      if (weeks != null) l10n.programWeekCount(weeks),
    ].join(' · ');
    return ListTile(
      title: Text(program.name),
      subtitle: Text(subtitle == null ? details : '$subtitle\n$details'),
      isThreeLine: subtitle != null,
      trailing: locked
          ? Icon(Icons.lock_outline, semanticLabel: l10n.catalogueLockedLabel)
          : const Icon(Icons.chevron_right),
      onTap: () => context.go(Routes.program(program.id!)),
    );
  }
}

/// This week, one row per planned or done program day.
class _WeekPlan extends StatelessWidget {
  const _WeekPlan({required this.program, required this.plan});

  final Program program;
  final List<PlannedDay> plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (plan.isEmpty) {
      return ListTile(dense: true, title: Text(l10n.programWeekEmpty));
    }
    return Column(
      children: [
        for (final day in plan)
          ListTile(
            dense: true,
            leading: Text(l10n.weekdayShort(day.date.weekday)),
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
