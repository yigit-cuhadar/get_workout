import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/text_length.dart';
import '../../../core/widgets/featured_card.dart';
import '../../../core/widgets/volume_band.dart';
import '../../../l10n/app_localizations.dart';
import '../../calculators/presentation/calculator_list.dart';
import '../../generator/presentation/generator_entry.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_editing.dart';
import '../../programs/domain/program_usecases.dart';
import '../../programs/presentation/missed_day_prompt.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/presentation/first_weekday.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../steps/domain/steps.dart';
import '../../subscription/presentation/premium.dart';
import '../../volume/domain/weekly_volume.dart';
import '../../volume/presentation/volume_charts.dart';
import '../../workout/domain/exercise_stats.dart';
import '../../workout/domain/workout.dart';
import '../../workout/presentation/active_workout_cubit.dart';
import '../../workout/presentation/elapsed_text.dart';
import '../../workout/presentation/start_workout.dart';
import '../../workout/presentation/workout_text.dart';
import 'next_workout.dart';
import 'today_steps_cubit.dart';
import 'today_volume_cubit.dart';
import 'today_week_cubit.dart';
import 'week_card.dart';
import 'widgets/rest_day_card.dart';

/// The Today tab: this week, the next workout, this week's volume, the
/// calculators and steps, each card on its own data, so one failing leaves
/// the others.
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firstWeekday = context.watchFirstWeekday();
    return MultiBlocProvider(
      providers: [
        // The Programs tab's, so both show the same plan.
        BlocProvider.value(value: sl<ProgramListCubit>()),
        BlocProvider(create: (_) => sl<TodayWeekCubit>(param1: firstWeekday)),
        BlocProvider(create: (_) => sl<TodayVolumeCubit>(param1: firstWeekday)),
        BlocProvider(create: (_) => sl<TodayStepsCubit>()),
      ],
      child: FirstWeekdayListener(
        created: firstWeekday,
        onChanged: (context, firstWeekday) {
          context.read<TodayWeekCubit>().changeFirstWeekday(firstWeekday);
          context.read<TodayVolumeCubit>().changeFirstWeekday(firstWeekday);
        },
        child: const _TodayView(),
      ),
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
    WeekCard(),
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
    appBar: ForgeAppBar(title: AppLocalizations.of(context).tabToday),
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

/// The one workout card, the only place a program day starts: the active
/// program's next day, the workout in progress, today's workout done, a
/// rest day, or the ways to train without a program day.
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
      today: context.select(
        (TodayWeekCubit cubit) =>
            (today: cubit.state.today, done: cubit.state.doneToday),
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
          locked: access == ProgramAccess.locked,
        ),
      RestDay() => _RestDayCard(next),
      DoneToday() => _DoneTodayCard(next),
      MissedProgramDay() => _MissedDayCard(next, busy: state.resolving),
      NoProgramDay(:final finished) => _NoProgramDay(finished),
      null when state.status != ProgramListStatus.failure =>
        FeaturedCard.loading(eyebrow: l10n.todayNextTitle),
      null => SectionCard.error(
        title: l10n.todayNextTitle,
        onTap: () => context.go(Routes.programs),
        message: l10n.programsLoadFailed,
        retryLabel: l10n.retry,
        onRetry: context.read<ProgramListCubit>().retry,
      ),
    };
  }
}

/// The workout in progress in place of the next one: where it is, the
/// time since it started, and the way back into it, as the workout bar.
class _WorkoutInProgressCard extends StatelessWidget {
  const _WorkoutInProgressCard(this.next);
  final WorkoutInProgress next;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    void open() => context.push(Routes.workout);
    return EverySecond(
      builder: (context) => FeaturedCard(
        form: FeaturedCardForm.block,
        eyebrow: l10n.todayWorkoutInProgress,
        // Its day's name, not the workout's "Program · Day".
        title: switch ((next.program, next.dayIndex)) {
          (final program?, final dayIndex?) => l10n.dayName(
            program.days[dayIndex],
            dayIndex,
          ),
          _ => next.name,
        },
        line: FeaturedLine(
          l10n.todayInProgressLine(
            next.exercise,
            next.exercises,
            next.doneSets,
          ),
          data: l10n.elapsedText(DateTime.now().difference(next.startedAt)),
        ),
        action: FeaturedAction(l10n.todayResumeWorkout, open),
        onTap: open,
      ),
    );
  }
}

/// A program day under its program's name, which opens the program: its
/// size and date (none when the program ends first), and Start, which goes
/// through the premium gate for a [locked] copy and asks first while a
/// workout is in progress.
class _ProgramDayCard extends StatelessWidget {
  const _ProgramDayCard(
    this.program,
    this.dayIndex, {
    required this.date,
    required this.locked,
  });

  final Program program;
  final int dayIndex;
  final CalendarDate? date;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final day = program.days[dayIndex];
    final name = l10n.dayName(day, dayIndex);
    final date = this.date;
    return FeaturedCard(
      form: FeaturedCardForm.block,
      eyebrow: program.name,
      locked: locked,
      title: name,
      line: FeaturedLine(
        _daySummary(l10n, day),
        data: date == null ? null : l10n.planDate(date),
      ),
      note: locked ? l10n.programLockedActive : null,
      action: FeaturedAction(
        l10n.workoutStartDay(name),
        () => startProgramDay(context, program, dayIndex),
        locked: locked,
      ),
      onTap: () => context.go(Routes.program(program.id!)),
    );
  }
}

String _daySummary(AppLocalizations l10n, ProgramDay day) =>
    l10n.todayDaySummary(day.items.length, l10n.estimateText(estimateDay(day)));

/// A day without a planned workout: the next day and its date, today's
/// steps toward the goal, cardio, the next day early and an empty workout.
class _RestDayCard extends StatelessWidget {
  const _RestDayCard(this.next);
  final RestDay next;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final steps = context.watch<TodayStepsCubit>().state;
    final goal = context.select(
      (SettingsCubit cubit) => cubit.state.settings.stepGoal,
    );
    final RestDay(:program, :dayIndex, :date, :access) = next;
    final name = l10n.dayName(program.days[dayIndex], dayIndex);
    return RestDayCard(
      next: l10n.todayDayOnDate(name, l10n.planDate(date)),
      nextDay: name,
      steps: steps.status == TodayStepsStatus.ready
          ? steps.progress?.steps
          : null,
      goal: steps.progress?.goal ?? goal,
      locked: access == ProgramAccess.locked,
      onSteps: () => context.go(Routes.steps),
      onLogCardio: () => context.go(Routes.cardioNew),
      onStartEarly: () => startProgramDay(context, program, dayIndex),
      onStartEmpty: () => startFreeWorkout(context),
    );
  }
}

/// The workout finished today, opening its page above Today, over the
/// next day, planned later, which opens the program like the block.
class _DoneTodayCard extends StatelessWidget {
  const _DoneTodayCard(this.next);
  final DoneToday next;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final DoneToday(:workout, :program, :dayIndex, :date) = next;
    final summary = summarizeWorkout(workout, const []);
    // A day's workout is named after it, its program first.
    final done =
        workout.programId == program.id &&
            workout.dayIndex != null &&
            workout.dayIndex! < program.days.length
        ? l10n.dayName(program.days[workout.dayIndex!], workout.dayIndex!)
        : workout.name;
    final day = program.days[dayIndex];
    void openProgram() => context.go(Routes.program(program.id!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        FeaturedCard(
          form: FeaturedCardForm.block,
          eyebrow: program.name,
          title: l10n.todayDoneTitle(done),
          line: FeaturedLine(
            l10n.todayDoneSummary(
              summary.setCount,
              l10n.durationMinutes(summary.duration),
            ),
            data: l10n.planDate(workout.startDate),
          ),
          action: FeaturedAction(
            l10n.todaySeeSummary,
            () => context.push(Routes.todayWorkout(workout.id)),
          ),
          onTap: openProgram,
        ),
        ListRowCard(
          children: [
            ListRow(
              leading: const ForgeIcon(ForgeIcons.event),
              title: l10n.todayNextDay(l10n.dayName(day, dayIndex)),
              detail: l10n.todayNextDayDetail(
                l10n.planDate(date),
                _daySummary(l10n, day),
              ),
              end: ListRowEnd.chevron,
              onTap: openProgram,
            ),
          ],
        ),
      ],
    );
  }
}

/// The active program's missed next day in a header band, which opens the
/// program, and the three ways to resolve it; Start comes back once it is
/// answered. While one is saved the buttons and the band do nothing.
class _MissedDayCard extends StatelessWidget {
  const _MissedDayCard(this.next, {required this.busy});

  final MissedProgramDay next;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final MissedProgramDay(:program, :missed, :moveDate) = next;
    final index = missed.dayIndex;
    final name = l10n.dayName(program.days[index], index);
    VoidCallback? resolve(MissedDayChoice choice) =>
        busy ? null : () => resolveMissedDay(context, choice);
    return FeaturedCard(
      form: FeaturedCardForm.band,
      eyebrow: program.name,
      title: name,
      line: FeaturedLine.missed(
        l10n.programMissedTitle(name, l10n.planDate(missed.date)),
        status: l10n.programDayMissed,
      ),
      action: FeaturedAction(
        l10n.programMissedToday,
        resolve(MissedDayChoice.doToday),
      ),
      moreActions: [
        FeaturedAction(
          l10n.programMissedMove(l10n.weekdayLong(moveDate.weekday)),
          resolve(MissedDayChoice.moveToNextWeekday),
        ),
        FeaturedAction(l10n.programMissedSkip, resolve(MissedDayChoice.skip)),
      ],
      onTap: busy ? null : () => context.go(Routes.program(program.id!)),
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
    return FeaturedCard(
      form: FeaturedCardForm.prompt,
      eyebrow: finished == null
          ? l10n.todayGetStarted
          : l10n.todayProgramFinishedEyebrow,
      title: finished == null
          ? l10n.todayPickFirstProgram
          : l10n.todayPickNextProgram,
      note: finished == null
          ? l10n.todayNoProgram
          : l10n.todayProgramFinished(finished.name),
      action: FeaturedAction(
        l10n.todaySeeReadyMade,
        () => context.go(Routes.catalogue),
      ),
      moreActions: [
        FeaturedAction(
          l10n.generatorTitle,
          () => openGenerator(context),
          locked: context.watchPremium() == PremiumStatus.free,
        ),
        FeaturedAction(l10n.workoutStartEmpty, () => startFreeWorkout(context)),
      ],
    );
  }
}

/// This week's sets: the total, the most trained muscles against the band
/// and how many trained muscles are in, below and above it. Opens weekly
/// volume.
class _VolumeCard extends StatelessWidget {
  const _VolumeCard();

  /// The most trained muscles shown.
  static const _topMuscles = 4;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<TodayVolumeCubit>().state;
    final title = l10n.todayVolumeTitle;
    void open() => context.go(Routes.volume);
    return switch ((state.status, state.week)) {
      (TodayVolumeStatus.failure, _) => SectionCard.error(
        title: title,
        onTap: open,
        message: l10n.volumeLoadFailed,
        retryLabel: l10n.retry,
        onRetry: context.read<TodayVolumeCubit>().retry,
      ),
      (TodayVolumeStatus.ready, final week?) => SectionCard(
        title: title,
        detail: l10n.todayVolumeTotal(week.totalSets),
        onTap: open,
        child: week.sets.isEmpty
            ? Text(
                l10n.todayVolumeEmpty,
                style: Theme.of(context).textTheme.bodySmall,
              )
            : _WeekVolume(week),
      ),
      _ => SectionCard.loading(title: title, onTap: open),
    };
  }
}

class _WeekVolume extends StatelessWidget {
  const _WeekVolume(this.week);
  final WeekVolume week;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final zones = week.zoneCounts;
    final scale = volumeScale(week.sets.values);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        for (final muscle in week.musclesBySets.take(_VolumeCard._topMuscles))
          if (week.setsOf(muscle) > 0)
            VolumeBand(muscle: muscle, sets: week.setsOf(muscle), scale: scale),
        Text(
          l10n.todayVolumeZones(
            zones[VolumeZone.within]!,
            zones[VolumeZone.below]!,
            zones[VolumeZone.above]!,
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Every calculator as a chip opening it; the card opens the list.
class _CalculatorsCard extends StatelessWidget {
  const _CalculatorsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      title: l10n.calculatorsTitle,
      onTap: () => context.go(Routes.calculators),
      child: Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.sm,
        children: [
          for (final (:title, subtitle: _, :route) in calculatorsOf(l10n))
            ForgeChip(label: title, onPressed: () => context.go(route)),
        ],
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
    final title = l10n.stepsTitle;
    return switch ((state.status, state.progress)) {
      (TodayStepsStatus.unavailable, _) => const SizedBox.shrink(),
      (TodayStepsStatus.setUp, _) => SectionCard.empty(
        title: title,
        onTap: open,
        message: l10n.todayStepsSetUp,
      ),
      (TodayStepsStatus.failure, _) => SectionCard.error(
        title: title,
        onTap: open,
        message: l10n.stepsLoadFailed,
        retryLabel: l10n.retry,
        onRetry: () => context.read<TodayStepsCubit>().load(
          context.read<SettingsCubit>().state.settings.stepGoal,
        ),
      ),
      (TodayStepsStatus.ready, final progress?) => SectionCard(
        title: title,
        onTap: open,
        child: _StepsProgress(progress),
      ),
      _ => SectionCard.loading(title: title, onTap: open),
    };
  }
}

class _StepsProgress extends StatelessWidget {
  const _StepsProgress(this.progress);
  final StepGoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Progress.bar(
      value: progress.steps.toDouble(),
      goal: progress.goal.toDouble(),
      figure: l10n.todayStepsFigure(progress.steps),
      caption: progress.reached
          ? l10n.stepsGoalReached
          : l10n.stepsToGo(progress.remaining),
    );
  }
}
