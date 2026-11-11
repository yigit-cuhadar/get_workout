import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/program.dart';
import '../domain/program_schedule.dart';
import 'program_list_cubit.dart';
import 'program_text.dart';

/// The Programs tab: the active program with this week's plan, then the
/// other programs.
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
    return BlocConsumer<ProgramListCubit, ProgramListState>(
      listenWhen: (_, current) => current.writeRejected,
      listener: (context, _) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.programWritesRejected)));
        _cubit.rejectionShown();
      },
      builder: (context, state) {
        final hasPrograms = state.programs.isNotEmpty;
        void create() => context.go(Routes.programNew);
        return Scaffold(
          appBar: AppBar(title: Text(l10n.tabPrograms)),
          floatingActionButton: hasPrograms
              ? FloatingActionButton.extended(
                  onPressed: create,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.programNew),
                )
              : null,
          body: switch (state.status) {
            ProgramListStatus.loading => const LoadingView(),
            ProgramListStatus.failure => ErrorView(
              message: l10n.programsLoadFailed,
              retryLabel: l10n.retry,
              onRetry: _cubit.retry,
            ),
            ProgramListStatus.ready when !hasPrograms => EmptyView(
              message: l10n.programsEmpty,
              action: ForgeButton(label: l10n.programNew, onPressed: create),
            ),
            ProgramListStatus.ready => _Programs(state),
          },
        );
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
    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.xl * 2),
      children: [
        if (active != null) ...[
          _Header(l10n.programActive),
          _ProgramTile(
            active,
            subtitle: state.finished
                ? l10n.programFinished
                : l10n.weekdayList(state.active!.weekdays),
          ),
          if (!state.finished) _WeekPlan(program: active, plan: state.weekPlan),
        ],
        if (others.isNotEmpty) ...[
          _Header(active == null ? l10n.programsMine : l10n.programsOther),
          for (final program in others) _ProgramTile(program),
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
  const _ProgramTile(this.program, {this.subtitle});

  final Program program;
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
      trailing: const Icon(Icons.chevron_right),
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
