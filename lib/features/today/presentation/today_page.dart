import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/first_weekday.dart';
import '../../../core/text_length.dart';
import '../../../l10n/app_localizations.dart';
import '../../calendar/presentation/calendar_marks.dart';
import '../../calendar/presentation/month_grid.dart';
import '../../calculators/presentation/calculator_list.dart';
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
import '../../workout/domain/workout.dart';
import '../../workout/presentation/active_workout_cubit.dart';
import '../../workout/presentation/start_workout.dart';
import 'next_workout.dart';
import 'today_steps_cubit.dart';
import 'today_volume_cubit.dart';
import 'today_week_cubit.dart';

/// The Today tab: this week, the next workout, this week's volume, the
/// calculators and steps, each card on its own data, so one failing leaves
/// the others.
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firstWeekday = MaterialLocalizations.of(context).firstWeekday;
    return MultiBlocProvider(
      key: ValueKey(firstWeekday),
      providers: [
        // Train's, so both show the same plan.
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
    _WeekCard(),
    _WorkoutCard(),
    _VolumeCard(),
    _CalculatorsCard(),
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

/// A card with a [title] row, under its [label] when given, and its
/// [detail] when given; the whole card opens [onOpen] when given. The
/// [prominent] one stands out in the theme's primary container.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.title,
    required this.child,
    this.label,
    this.detail,
    this.onOpen,
    this.prominent = false,
  });

  final String title;
  final String? label;
  final String? detail;
  final VoidCallback? onOpen;
  final bool prominent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    final detail = this.detail;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = prominent ? colors.onPrimaryContainer : null;
    final titleText = Text(
      title,
      style:
          (prominent ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)
              ?.copyWith(color: foreground),
    );
    final trailing = [
      if (detail != null) Text(detail),
      if (onOpen != null) const Icon(Icons.chevron_right),
    ];
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: prominent ? colors.primaryContainer : null,
      child: ListTileTheme.merge(
        textColor: foreground,
        iconColor: foreground,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: InkWell(
              onTap: onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: ListTile(
                      title: label == null
                          ? titleText
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colors.primary,
                                  ),
                                ),
                                titleText,
                              ],
                            ),
                      trailing: trailing.isEmpty
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: trailing,
                            ),
                    ),
                  ),
                  child,
                ],
              ),
            ),
          ),
        ),
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

/// The one workout card, the only place a program day starts: the active
/// program's next day, the workout in progress, or the ways to train
/// without a program day.
class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ProgramListCubit>().state;
    final next = nextWorkoutOf(
      state,
      context.select(
        (ActiveWorkoutCubit cubit) => activeWorkoutViewOf(cubit.state),
      ),
      // As startProgramDay names it.
      startName: (program, dayIndex) => cutToLength(
        l10n.workoutProgramDayName(
          program.name,
          l10n.dayName(program.days[dayIndex], dayIndex),
        ),
        WorkoutLimits.maxNameLength,
      ),
    );
    return switch (next) {
      WorkoutInProgress() => _WorkoutInProgressCard(next),
      NextProgramDay(
        :final program,
        :final dayIndex,
        :final date,
        :final access,
      ) =>
        _ProgramDayCard(
          program,
          dayIndex,
          date: date,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: Gap.md),
            ],
          ),
        ),
      MissedProgramDay(:final program, :final missed, :final moveDate) =>
        _ProgramDayCard(
          program,
          missed.dayIndex,
          child: MissedDayPrompt(
            program: program,
            missed: missed,
            moveDate: moveDate,
            busy: state.resolving,
          ),
        ),
      _ => _TodayCard(
        prominent: true,
        title: l10n.todayNextTitle,
        child: switch (next) {
          null when state.status == ProgramListStatus.failure => ErrorView(
            message: l10n.programsLoadFailed,
            retryLabel: l10n.retry,
            onRetry: context.read<ProgramListCubit>().retry,
          ),
          NoProgramDay(:final finished) => _NoProgramDay(finished),
          _ => const _Loading(),
        },
      ),
    };
  }
}

/// The workout in progress in place of the next one: its name, the program
/// day it was started from, and the way back into it, as the workout bar.
class _WorkoutInProgressCard extends StatelessWidget {
  const _WorkoutInProgressCard(this.next);
  final WorkoutInProgress next;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    void open() => context.push(Routes.workout);
    return _TodayCard(
      prominent: true,
      label: l10n.todayWorkoutInProgress,
      title: next.name,
      onOpen: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((next.program, next.dayIndex) case (
            final program?,
            final dayIndex?,
          ))
            ListTile(
              leading: const Icon(Icons.fitness_center),
              title: Text(l10n.dayName(program.days[dayIndex], dayIndex)),
              subtitle: Text(program.name),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
            child: ForgeButton(label: l10n.todayResumeWorkout, onPressed: open),
          ),
        ],
      ),
    );
  }
}

/// A program day under its program's name, which opens the program: its
/// size, Start, which goes through the premium gate for a locked copy and
/// asks first while a workout is in progress, then [child].
class _ProgramDayCard extends StatelessWidget {
  const _ProgramDayCard(
    this.program,
    this.dayIndex, {
    required this.child,
    this.date,
  });

  final Program program;
  final int dayIndex;

  /// When it is planned; a missed day says so itself.
  final CalendarDate? date;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final day = program.days[dayIndex];
    final name = l10n.dayName(day, dayIndex);
    final date = this.date;
    return _TodayCard(
      prominent: true,
      label: program.name,
      title: name,
      onOpen: () => context.go(Routes.program(program.id!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.fitness_center),
            title: Text(
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
          child,
        ],
      ),
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

/// This week's sets: the total, the most trained muscles against the band
/// and how many trained muscles are in, below and above it. Opens weekly
/// volume.
class _VolumeCard extends StatelessWidget {
  const _VolumeCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<TodayVolumeCubit>().state;
    final week = state.week;
    return _TodayCard(
      title: l10n.todayVolumeTitle,
      detail: week == null || week.sets.isEmpty
          ? null
          : l10n.todayVolumeTotal(week.totalSets),
      onOpen: () => context.go(Routes.volume),
      child: switch ((state.status, week)) {
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

  /// The most trained muscles shown.
  static const _topMuscles = 4;

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final muscle in week.musclesBySets.take(_topMuscles))
            if (week.setsOf(muscle) > 0) ...[
              Row(
                children: [
                  Expanded(child: Text(l10n.muscleName(muscle))),
                  Text(l10n.setsText(week.setsOf(muscle))),
                ],
              ),
              const SizedBox(height: Gap.xs),
              VolumeBandBar(sets: week.setsOf(muscle), scale: scale),
              const SizedBox(height: Gap.sm),
            ],
          Text(
            l10n.todayVolumeZones(
              zones[VolumeZone.within]!,
              zones[VolumeZone.below]!,
              zones[VolumeZone.above]!,
            ),
          ),
        ],
      ),
    );
  }
}

/// Every calculator as a chip opening it; the card opens the list.
class _CalculatorsCard extends StatelessWidget {
  const _CalculatorsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _TodayCard(
      title: l10n.calculatorsTitle,
      onOpen: () => context.go(Routes.calculators),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
        child: Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final (:title, subtitle: _, :route) in calculatorsOf(l10n))
              ActionChip(
                label: Text(title),
                onPressed: () => context.go(route),
              ),
          ],
        ),
      ),
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
          Text(
            l10n.stepsCount(progress.steps),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(l10n.stepsOfGoal(progress.goal)),
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
