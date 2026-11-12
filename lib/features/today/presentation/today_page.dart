import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/first_weekday.dart';
import '../../../l10n/app_localizations.dart';
import '../../calendar/presentation/calendar_marks.dart';
import '../../calendar/presentation/month_grid.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../generator/presentation/generator_entry.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_editing.dart';
import '../../programs/presentation/missed_day_prompt.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../steps/domain/steps.dart';
import '../../volume/domain/weekly_volume.dart';
import '../../volume/presentation/volume_charts.dart';
import '../../volume/presentation/volume_text.dart';
import '../../workout/presentation/start_workout.dart';
import 'next_workout.dart';
import 'today_steps_cubit.dart';
import 'today_volume_cubit.dart';
import 'today_week_cubit.dart';

/// The Today tab: the next workout, this week, quick actions and this
/// week's volume, each card on its own data, so one failing leaves the
/// others.
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firstWeekday = MaterialLocalizations.of(context).firstWeekday;
    return MultiBlocProvider(
      key: ValueKey(firstWeekday),
      providers: [
        // The Programs tab's, so both show the same plan.
        BlocProvider.value(value: sl<ProgramListCubit>()),
        BlocProvider(create: (_) => sl<TodayWeekCubit>(param1: firstWeekday)),
        BlocProvider(create: (_) => sl<TodayVolumeCubit>(param1: firstWeekday)),
        BlocProvider(create: (_) => sl<TodayStepsCubit>()),
      ],
      child: const _TodayView(),
    );
  }
}

class _TodayView extends StatefulWidget {
  const _TodayView();

  @override
  State<_TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<_TodayView> {
  late final AppLifecycleListener _lifecycle;

  /// Independent cards, in order.
  static const _cards = [
    _NextWorkoutCard(),
    _WeekCard(),
    _QuickActionsCard(),
    _VolumeCard(),
    _StepsCard(),
  ];

  /// Today moves on while the app sleeps, without a new snapshot to
  /// recompute it.
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshNow);
    context.read<ProgramListCubit>().refreshNow();
    _loadSteps();
  }

  void _refreshNow() {
    context.read<ProgramListCubit>().refreshNow();
    context.read<TodayWeekCubit>().refreshNow();
    context.read<TodayVolumeCubit>().refreshNow();
    // Steps are read, never followed, and may change in the health store.
    _loadSteps();
  }

  void _loadSteps() => context.read<TodayStepsCubit>().load(
    context.read<SettingsCubit>().state.settings.stepGoal,
  );

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).tabToday)),
    body: BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (previous, current) =>
          previous.settings.stepGoal != current.settings.stepGoal,
      listener: (_, _) => _loadSteps(),
      child: ListView.separated(
        padding: const EdgeInsets.all(Gap.md),
        itemCount: _cards.length,
        separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
        itemBuilder: (_, index) => _cards[index],
      ),
    ),
  );
}

/// A card with a [title] row, which opens [onOpen] when given.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.onOpen,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: ListTile(
              title: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: subtitle == null ? null : Text(subtitle),
              trailing: onOpen == null ? null : const Icon(Icons.chevron_right),
              onTap: onOpen,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A card's body while its data loads: its title only. Data comes from
/// Firestore's cache at once, so a spinner on the home tab would only
/// flash.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const SizedBox(height: Gap.md);
}

class _NextWorkoutCard extends StatelessWidget {
  const _NextWorkoutCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ProgramListCubit>().state;
    final next = nextWorkoutOf(state);
    final program = switch (next) {
      NextProgramDay(:final program) ||
      MissedProgramDay(:final program) => program,
      _ => null,
    };
    return _TodayCard(
      title: l10n.todayNextTitle,
      subtitle: program?.name,
      onOpen: program == null
          ? null
          : () => context.go(Routes.program(program.id!)),
      child: switch (next) {
        null when state.status == ProgramListStatus.failure => ErrorView(
          message: l10n.programsLoadFailed,
          retryLabel: l10n.retry,
          onRetry: context.read<ProgramListCubit>().retry,
        ),
        null => const _Loading(),
        NoProgramDay(:final finished) => _NoProgramDay(finished),
        NextProgramDay(
          :final program,
          :final dayIndex,
          :final date,
          :final access,
        ) =>
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProgramDay(program, dayIndex, date: date),
              if (access == ProgramAccess.locked)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline),
                      const SizedBox(width: Gap.sm),
                      Expanded(child: Text(l10n.programLockedActive)),
                    ],
                  ),
                ),
              const SizedBox(height: Gap.sm),
            ],
          ),
        MissedProgramDay(:final program, :final missed, :final moveDate) =>
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProgramDay(program, missed.dayIndex),
              MissedDayPrompt(
                program: program,
                missed: missed,
                moveDate: moveDate,
                busy: state.resolving,
              ),
            ],
          ),
      },
    );
  }
}

/// A program day with its size and Start, which goes through the premium
/// gate for a locked copy and asks first while a workout is in progress.
class _ProgramDay extends StatelessWidget {
  const _ProgramDay(this.program, this.dayIndex, {this.date});

  final Program program;
  final int dayIndex;

  /// When it is planned; a missed day says so itself.
  final CalendarDate? date;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final day = program.days[dayIndex];
    final name = l10n.dayName(day, dayIndex);
    final date = this.date;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.fitness_center),
          title: Text(name),
          subtitle: Text(
            l10n.todayDaySummary(
              day.items.length,
              l10n.estimateText(estimateDay(day)),
            ),
          ),
          trailing: date == null ? null : Text(l10n.planDate(date)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: ForgeButton(
            label: l10n.workoutStartDay(name),
            onPressed: () => startProgramDay(context, program, dayIndex),
          ),
        ),
      ],
    );
  }
}

/// No program day to do: the ways to a program, or to just train.
class _NoProgramDay extends StatelessWidget {
  const _NoProgramDay(this.finished);
  final Program? finished;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final finished = this.finished;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            finished == null
                ? l10n.todayNoProgram
                : l10n.todayProgramFinished(finished.name),
          ),
          const SizedBox(height: Gap.md),
          ForgeButton(
            label: l10n.catalogueBrowse,
            onPressed: () => context.go(Routes.catalogue),
          ),
          const SizedBox(height: Gap.sm),
          const GeneratorButton(),
          const SizedBox(height: Gap.sm),
          OutlinedButton(
            onPressed: () => startFreeWorkout(context),
            child: Text(l10n.workoutStartEmpty),
          ),
        ],
      ),
    );
  }
}

/// This week as one calendar row; it, and every day of it, opens the
/// calendar, which has no route for a given date.
class _WeekCard extends StatelessWidget {
  const _WeekCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<TodayWeekCubit>().state;
    void open() => context.go(Routes.calendar);
    return _TodayCard(
      title: l10n.todayWeekTitle,
      onOpen: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // While loading the dates show without marks, as on the calendar.
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.sm, Gap.sm),
            child: MonthGrid(
              weeks: [state.days],
              selected: state.today,
              today: state.today,
              onSelected: (_) => open(),
              marks: (date) =>
                  calendarMarkIcons(context, state.entriesOn(date)),
              semanticLabel: (date) =>
                  calendarDayLabel(context, date, state.entriesOn(date)),
            ),
          ),
          if (state.status == TodayWeekStatus.failure)
            ErrorView(
              message: l10n.todayWeekLoadFailed,
              retryLabel: l10n.retry,
              onRetry: context.read<TodayWeekCubit>().retry,
            ),
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _TodayCard(
      title: l10n.todayQuickTitle,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: Text(l10n.workoutStartEmpty),
            onTap: () => startFreeWorkout(context),
          ),
          ListTile(
            leading: const Icon(Icons.directions_run),
            title: Text(l10n.cardioLog),
            onTap: () => context.go(Routes.cardioNew),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.historyAddPast),
            onTap: () => context.go(Routes.historyNew),
          ),
          ListTile(
            leading: const Icon(Icons.calculate_outlined),
            title: Text(l10n.calculatorsTitle),
            onTap: () => context.go(Routes.calculators),
          ),
        ],
      ),
    );
  }
}

/// This week's sets against the band: how many trained muscles are in,
/// below and above it, and the most trained ones. Opens weekly volume.
class _VolumeCard extends StatelessWidget {
  const _VolumeCard();

  /// The most trained muscles shown.
  static const _topMuscles = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<TodayVolumeCubit>().state;
    return _TodayCard(
      title: l10n.todayVolumeTitle,
      onOpen: () => context.go(Routes.volume),
      child: switch ((state.status, state.week)) {
        (TodayVolumeStatus.failure, _) => ErrorView(
          message: l10n.volumeLoadFailed,
          retryLabel: l10n.retry,
          onRetry: context.read<TodayVolumeCubit>().retry,
        ),
        (TodayVolumeStatus.ready, final week?) => _WeekVolume(week),
        _ => const _Loading(),
      },
    );
  }
}

class _WeekVolume extends StatelessWidget {
  const _WeekVolume(this.week);
  final WeekVolume week;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (week.sets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
        child: Text(l10n.volumeNoWorkoutsThisWeek),
      );
    }
    final zones = week.zoneCounts;
    final scale = volumeScale(week.sets.values);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Text(
            l10n.todayVolumeZones(
              zones[VolumeZone.within]!,
              zones[VolumeZone.below]!,
              zones[VolumeZone.above]!,
            ),
          ),
        ),
        for (final muscle in week.musclesBySets.take(_VolumeCard._topMuscles))
          if (week.setsOf(muscle) > 0)
            ListTile(
              title: Text(l10n.muscleName(muscle)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: VolumeBandBar(sets: week.setsOf(muscle), scale: scale),
              ),
              trailing: Text(l10n.setsText(week.setsOf(muscle))),
              onTap: () => context.go(Routes.volume),
            ),
      ],
    );
  }
}

/// Today's steps against the daily goal; opens the Steps page, which also
/// sets access up. No card on a device without a health store.
class _StepsCard extends StatelessWidget {
  const _StepsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<TodayStepsCubit>().state;
    void open() => context.go(Routes.steps);
    if (state.status == TodayStepsStatus.unavailable) {
      return const SizedBox.shrink();
    }
    return _TodayCard(
      title: l10n.stepsTitle,
      onOpen: open,
      child: switch ((state.status, state.progress)) {
        (TodayStepsStatus.setUp, _) => ListTile(
          leading: const Icon(Icons.directions_walk),
          title: Text(l10n.todayStepsSetUp),
          onTap: open,
        ),
        (TodayStepsStatus.failure, _) => ErrorView(
          message: l10n.stepsLoadFailed,
          retryLabel: l10n.retry,
          onRetry: () => context.read<TodayStepsCubit>().load(
            context.read<SettingsCubit>().state.settings.stepGoal,
          ),
        ),
        (TodayStepsStatus.ready, final progress?) => _StepsProgress(progress),
        _ => const _Loading(),
      },
    );
  }
}

class _StepsProgress extends StatelessWidget {
  const _StepsProgress(this.progress);
  final StepGoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.todayStepsProgress(progress.steps, progress.goal)),
          const SizedBox(height: Gap.sm),
          LinearProgressIndicator(value: progress.fraction),
          const SizedBox(height: Gap.sm),
          Text(
            progress.reached
                ? l10n.stepsGoalReached
                : l10n.stepsToGo(progress.remaining),
          ),
        ],
      ),
    );
  }
}
