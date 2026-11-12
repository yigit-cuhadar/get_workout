import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../cardio/presentation/cardio_text.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program_schedule.dart';
import '../../programs/presentation/program_text.dart';
import '../../workout/domain/exercise_stats.dart';
import '../../workout/presentation/start_workout.dart';
import '../../workout/presentation/workout_text.dart';
import '../domain/calendar_month.dart';
import 'calendar_cubit.dart';
import 'month_grid.dart';

/// A month of finished workouts, cardio and planned program days, with the
/// selected day's entries below it.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<CalendarCubit>(),
    child: const _CalendarView(),
  );
}

class _CalendarView extends StatelessWidget {
  const _CalendarView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    // 0 is Sunday; the grid takes ISO weekdays.
    final firstWeekday = dates.firstDayOfWeekIndex == 0
        ? DateTime.sunday
        : dates.firstDayOfWeekIndex;
    final cubit = context.read<CalendarCubit>();
    return BlocBuilder<CalendarCubit, CalendarState>(
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text(l10n.calendarTitle)),
        body: ListView(
          padding: const EdgeInsets.only(bottom: Gap.xl),
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: l10n.calendarPreviousMonth,
                  onPressed: () => cubit.showMonth(-1),
                ),
                Expanded(
                  child: Text(
                    dates.formatMonthYear(state.month.toLocalDateTime()),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: l10n.calendarNextMonth,
                  onPressed: () => cubit.showMonth(1),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
              child: MonthGrid(
                weeks: monthWeeks(state.month, firstWeekday: firstWeekday),
                month: state.month,
                selected: state.selected,
                today: state.today,
                onSelected: cubit.select,
                marks: (date) => _marks(context, state.entriesOn(date)),
                semanticLabel: (date) => [
                  dates.formatFullDate(date.toLocalDateTime()),
                  for (final kind in _kinds(state.entriesOn(date)))
                    _markLabel(l10n, kind),
                ].join(', '),
              ),
            ),
            const Divider(),
            switch (state.status) {
              CalendarStatus.loading => const Padding(
                padding: EdgeInsets.all(Gap.lg),
                child: LoadingView(),
              ),
              CalendarStatus.failure => ErrorView(
                message: l10n.calendarLoadFailed,
                retryLabel: l10n.retry,
                onRetry: cubit.retry,
              ),
              CalendarStatus.ready => _Day(
                date: state.selected,
                entries: state.entriesOn(state.selected),
              ),
            },
          ],
        ),
      ),
    );
  }
}

enum _Kind { workout, cardio, planned, missed }

/// The kinds of [entries], each once, in a fixed order.
List<_Kind> _kinds(List<CalendarEntry> entries) {
  final kinds = {
    for (final entry in entries)
      switch (entry) {
        WorkoutEntry() => _Kind.workout,
        CardioEntry() => _Kind.cardio,
        PlanEntry(:final day) =>
          day.status == PlannedStatus.missed ? _Kind.missed : _Kind.planned,
      },
  };
  return [
    for (final kind in _Kind.values)
      if (kinds.contains(kind)) kind,
  ];
}

String _markLabel(AppLocalizations l10n, _Kind kind) => switch (kind) {
  _Kind.workout => l10n.calendarWorkoutMark,
  _Kind.cardio => l10n.calendarCardioMark,
  _Kind.planned => l10n.calendarPlannedMark,
  _Kind.missed => l10n.calendarMissedMark,
};

List<Widget> _marks(BuildContext context, List<CalendarEntry> entries) {
  final colors = Theme.of(context).colorScheme;
  return [
    for (final kind in _kinds(entries))
      Icon(
        switch (kind) {
          _Kind.workout || _Kind.cardio => Icons.circle,
          _Kind.planned || _Kind.missed => Icons.circle_outlined,
        },
        size: Gap.sm,
        color: switch (kind) {
          _Kind.workout || _Kind.planned => colors.primary,
          _Kind.cardio => colors.tertiary,
          _Kind.missed => colors.error,
        },
      ),
  ];
}

/// The entries of the selected [date].
class _Day extends StatelessWidget {
  const _Day({required this.date, required this.entries});

  final CalendarDate date;
  final List<CalendarEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          title: Text(
            dates.formatFullDate(date.toLocalDateTime()),
            style: theme.textTheme.titleSmall,
          ),
        ),
        if (entries.isEmpty)
          ListTile(title: Text(l10n.calendarDayEmpty))
        else
          for (final entry in entries)
            switch (entry) {
              WorkoutEntry() => _WorkoutTile(entry),
              CardioEntry() => _CardioTile(entry),
              PlanEntry() => _PlanTile(entry),
            },
      ],
    );
  }
}

String _time(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(time));

class _WorkoutTile extends StatelessWidget {
  const _WorkoutTile(this.entry);
  final WorkoutEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workout = entry.workout;
    final summary = summarizeWorkout(workout, const []);
    return ListTile(
      leading: Icon(
        Icons.fitness_center,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(workout.name),
      subtitle: Text(
        '${_time(context, workout.startedAt)} · '
        '${l10n.durationMinutes(summary.duration)}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.historyWorkout(workout.id)),
    );
  }
}

class _CardioTile extends StatelessWidget {
  const _CardioTile(this.entry);
  final CardioEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = entry.session;
    return ListTile(
      leading: Icon(
        Icons.directions_run,
        color: Theme.of(context).colorScheme.tertiary,
      ),
      title: Text(l10n.typeName(session.type)),
      subtitle: Text(
        '${_time(context, session.date)} · '
        '${formatDuration(session.duration)}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.cardioSession(session.id!)),
    );
  }
}

/// A program day not done yet. A planned one starts like the program's own
/// ▶; a missed one is resolved on the Programs tab.
class _PlanTile extends StatelessWidget {
  const _PlanTile(this.entry);
  final PlanEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final PlanEntry(:program, :day) = entry;
    final name = l10n.dayName(program.days[day.dayIndex], day.dayIndex);
    final missed = day.status == PlannedStatus.missed;
    return ListTile(
      leading: Icon(
        missed ? Icons.error_outline : Icons.schedule,
        color: missed ? colors.error : colors.primary,
      ),
      title: Text(name),
      subtitle: Text(
        missed
            ? l10n.calendarMissed(program.name)
            : l10n.calendarPlanned(program.name),
      ),
      trailing: missed
          ? null
          : IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: l10n.workoutStartDay(name),
              onPressed: () => startProgramDay(context, program, day.dayIndex),
            ),
    );
  }
}
