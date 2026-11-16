import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/page_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../cardio/presentation/cardio_text.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_schedule.dart';
import '../../programs/domain/program_usecases.dart';
import '../../programs/presentation/missed_day_prompt.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/presentation/first_weekday.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../workout/domain/exercise_stats.dart';
import '../../workout/presentation/add_past_workout_sheet.dart';
import '../../workout/presentation/start_workout.dart';
import '../../workout/presentation/workout_text.dart';
import '../domain/calendar_days.dart';
import '../domain/calendar_month.dart';
import 'calendar_cubit.dart';
import 'calendar_marks.dart';

/// A month of finished workouts, cardio and program days: the month card
/// with its marks, a filter, then the month's days by week, newest first.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firstWeekday = context.watchFirstWeekday();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<CalendarCubit>(param1: firstWeekday)),
        BlocProvider.value(value: sl<ProgramListCubit>()),
      ],
      child: FirstWeekdayListener(
        created: firstWeekday,
        onChanged: (context, firstWeekday) =>
            context.read<CalendarCubit>().changeFirstWeekday(firstWeekday),
        child: const _CalendarView(),
      ),
    );
  }
}

class _CalendarView extends StatefulWidget {
  const _CalendarView();

  @override
  State<_CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<_CalendarView> {
  /// The first row of each listed date, to scroll to.
  final _rows = <CalendarDate, GlobalKey>{};

  /// The date the user tapped in the month, until the month changes.
  CalendarDate? _tapped;

  GlobalKey _keyOf(CalendarDate date) => _rows.putIfAbsent(date, GlobalKey.new);

  void _tap(DateTime day) {
    final date = CalendarDate.of(day);
    final cubit = context.read<CalendarCubit>();
    final otherMonth = monthOf(date) != cubit.state.month;
    cubit.select(date);
    setState(() => _tapped = otherMonth ? null : date);
    if (otherMonth) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _rows[date]?.currentContext;
      if (row != null && row.mounted) {
        unawaited(
          Scrollable.ensureVisible(
            row,
            duration: kThemeAnimationDuration,
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  void _move(int steps) {
    context.read<CalendarCubit>().move(steps);
    setState(() => _tapped = null);
  }

  Future<void> _pickMonth() async {
    final cubit = context.read<CalendarCubit>();
    final picked = await showDatePicker(
      context: context,
      initialDate: cubit.state.selected.toLocalDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (picked == null || !mounted) return;
    cubit.select(CalendarDate.of(picked));
    setState(() => _tapped = null);
  }

  Future<void> _addPast() async {
    final plan = await askPastWorkout(context);
    if (plan != null && mounted) {
      unawaited(context.push(Routes.calendarWorkoutNew, extra: plan));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<CalendarCubit, CalendarState>(
      listenWhen: (_, current) => current.writeRejected,
      listener: (context, _) {
        showForgeSnackbar(
          context,
          message: l10n.historyWritesRejected,
          error: true,
        );
        context.read<CalendarCubit>().rejectionShown();
      },
      builder: (context, state) {
        _rows.clear();
        final tapped = _tapped;
        return Scaffold(
          appBar: ForgeAppBar(
            title: l10n.calendarTitle,
            actions: [
              ForgeAppBarAction.icon(
                icon: ForgeIcons.add,
                label: l10n.calendarAddPast,
                onPressed: _addPast,
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.sm,
              children: [
                PeriodSelector(
                  period: DateFormat.yMMMM(l10n.localeName)
                      .format(state.month.toLocalDateTime()),
                  onPrevious: () => _move(-1),
                  onNext: () => _move(1),
                  onPeriodTap: _pickMonth,
                  previousLabel: l10n.calendarPreviousMonth,
                  nextLabel: l10n.calendarNextMonth,
                ),
                _Month(state, selected: tapped, onDayTap: _tap),
                ..._list(context, state, tapped),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The filter, the tapped date when the list does not hold it, and the
  /// month's sections; or what stands in their place.
  List<Widget> _list(
    BuildContext context,
    CalendarState state,
    CalendarDate? tapped,
  ) {
    final l10n = AppLocalizations.of(context);
    final firstWeekday = context.watchFirstWeekday();
    final monthName = DateFormat.MMMM(l10n.localeName)
        .format(state.month.toLocalDateTime());
    switch (state.status) {
      case CalendarStatus.failure:
        return const [];
      case CalendarStatus.loading:
        return [
          _Filter(state.filter),
          const SkeletonBar(widthFactor: 0.3, height: 10),
          const ListRowCard(
            children: [
              ListRow.loading(),
              ListRow.loading(index: 1),
              ListRow.loading(index: 2),
            ],
          ),
        ];
      case CalendarStatus.ready:
    }
    final sections = monthSections(
      state.month,
      today: state.today,
      firstWeekday: firstWeekday,
      entriesOn: state.entriesOn,
    );
    final everything = monthSections(
      state.month,
      today: state.today,
      firstWeekday: firstWeekday,
      entriesOn: (date) => state.entries[date] ?? const [],
    );
    final logged = everything.any(
      (section) => section.days.any(
        (day) => day.entries.any((entry) => entry is! PlanEntry),
      ),
    );
    final listed = {
      for (final section in sections)
        for (final day in section.days) day.date,
    };
    final pinned = tapped != null && !listed.contains(tapped)
        ? calendarDay(tapped, state.entriesOn(tapped))
        : null;
    final empty = switch (state.filter) {
      _ when !logged => _EmptyCard(
        title: l10n.calendarEmptyTitle(monthName),
        message: l10n.calendarEmptyDetail,
        action: l10n.calendarAddPast,
        onPressed: _addPast,
      ),
      CalendarFilter.workouts when sections.isEmpty => _EmptyCard(
        title: l10n.calendarNoWorkouts(monthName),
        message: l10n.calendarNoWorkoutsDetail,
        action: l10n.calendarAddPast,
        onPressed: _addPast,
      ),
      CalendarFilter.cardio when sections.isEmpty => _EmptyCard(
        title: l10n.calendarNoCardio(monthName),
        message: l10n.calendarNoCardioDetail,
        action: l10n.cardioLog,
        onPressed: () => context.go(Routes.cardioNew),
      ),
      _ => null,
    };
    return [
      // A month with nothing logged has nothing to filter.
      if (logged) _Filter(state.filter),
      if (pinned != null) ...[
        SectionLabel(l10n.planDate(pinned.date)),
        if (pinned.entries.isEmpty)
          SurfaceCard(
            child: Text(
              l10n.calendarDayEmpty,
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(color: ForgeStyle.of(context).colors.inkMuted),
            ),
          )
        else
          ListRowCard(children: _dayRows(context, state, pinned)),
      ],
      for (final section in sections) ...[
        SectionLabel(switch (section.kind) {
          CalendarSectionKind.thisWeek => l10n.calendarThisWeek(
            l10n.dateRange(section.first, section.last),
          ),
          CalendarSectionKind.earlierThisMonth => l10n.calendarEarlierThisMonth,
          CalendarSectionKind.week => l10n.dateRange(
            section.first,
            section.last,
          ),
        }),
        ListRowCard(
          children: [
            for (final day in section.days) ..._dayRows(context, state, day),
          ],
        ),
      ],
      ?empty,
    ];
  }

  List<Widget> _dayRows(
    BuildContext context,
    CalendarState state,
    CalendarDay day,
  ) => [
    for (final (i, entry) in day.entries.indexed)
      KeyedSubtree(
        key: i == 0 ? _keyOf(day.date) : null,
        child: _EntryRow(entry: entry, today: day.date == state.today),
      ),
  ];
}

/// The month's circles with their marks, the summary and the legend; the
/// tapped date ringed.
class _Month extends StatelessWidget {
  const _Month(this.state, {required this.selected, required this.onDayTap});

  final CalendarState state;
  final CalendarDate? selected;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final firstWeekday = context.watchFirstWeekday();
    final narrow = MaterialLocalizations.of(context).narrowWeekdays;
    // Sunday first; ISO 7 is Sunday.
    final weekdays = [
      for (var i = 0; i < 7; i++) narrow[(firstWeekday + i) % 7],
    ];
    return switch (state.status) {
      CalendarStatus.loading => MonthGrid.loading(weekdays: weekdays),
      CalendarStatus.failure => MonthGrid.error(
        weekdays: weekdays,
        message: l10n.calendarLoadFailed,
        retryLabel: l10n.retry,
        onRetry: context.read<CalendarCubit>().retry,
      ),
      CalendarStatus.ready => MonthGrid(
        month: state.month.toLocalDateTime(),
        firstWeekday: firstWeekday,
        weekdays: weekdays,
        stateOf: (day) {
          final date = CalendarDate.of(day);
          return calendarDayState(
            state.entriesOn(date),
            today: date == state.today,
          );
        },
        summary: _summary(l10n, monthCounts(state.month, state.entriesOn)),
        legend: calendarLegend(l10n),
        selected: selected?.toLocalDateTime(),
        onDayTap: onDayTap,
      ),
    };
  }

  /// "4 workouts · 4 cardio · 1 missed", leaving out what is none; none
  /// for a month with nothing.
  String? _summary(AppLocalizations l10n, MonthCounts counts) {
    final parts = [
      if (counts.workouts > 0) l10n.calendarSummaryWorkouts(counts.workouts),
      if (counts.cardio > 0) l10n.calendarSummaryCardio(counts.cardio),
      if (counts.missed > 0) l10n.calendarSummaryMissed(counts.missed),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// All, Workouts or Cardio.
class _Filter extends StatelessWidget {
  const _Filter(this.filter);
  final CalendarFilter filter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<CalendarCubit>();
    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        for (final (value, label) in [
          (CalendarFilter.all, l10n.calendarFilterAll),
          (CalendarFilter.workouts, l10n.calendarFilterWorkouts),
          (CalendarFilter.cardio, l10n.calendarFilterCardio),
        ])
          ForgeChip(
            label: label,
            selected: value == filter,
            showCheck: false,
            onPressed: () => cubit.filter(value),
          ),
      ],
    );
  }
}

/// A month or filter with nothing to list: its line and an action, in a
/// card.
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.title,
    required this.message,
    required this.action,
    required this.onPressed,
  });

  final String title;
  final String message;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: EmptyView(
      icon: ForgeIcons.event,
      title: title,
      message: message,
      compact: true,
      actions: [
        ForgeButton(
          label: action,
          variant: ForgeButtonVariant.secondary,
          onPressed: onPressed,
        ),
      ],
    ),
  );
}

/// One entry of a date: its date box (today's ringed), then a workout or a
/// cardio session opening its page, a planned day with Start, or a missed
/// one with Do it today. Holding the program's next day, planned or
/// missed, moves it.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.today});

  final CalendarEntry entry;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final date = entry.date.toLocalDateTime();
    final box = ListRowDateBox(
      weekday: DateFormat.E(l10n.localeName).format(date),
      day: '${date.day}',
      state: today ? DayState.today : DayState.none,
    );
    switch (entry) {
      case WorkoutEntry(:final workout):
        final unit = context.select(
          (SettingsCubit cubit) => cubit.state.settings.weightUnit,
        );
        final summary = summarizeWorkout(workout);
        return ListRow(
          leading: box,
          title: workout.name,
          detail: [
            l10n.durationMinutes(summary.duration),
            if (summary.volumeKg > 0)
              l10n.weightText(summary.volumeKg, unit)
            else
              l10n.historySetCount(summary.setCount),
          ].join(' · '),
          end: ListRowEnd.chevron,
          onTap: () => context.go(Routes.calendarWorkout(workout.id)),
        );
      case CardioEntry(:final session):
        final unit = context.select(
          (SettingsCubit cubit) =>
              distanceUnitFor(cubit.state.settings.lengthUnit),
        );
        final distance = session.distanceKm;
        return ListRow(
          leading: box,
          title: l10n.typeName(session.type),
          detail: l10n.calendarRowCardio(
            distance == null
                ? l10n.cardioMinutesOf(session.duration)
                : l10n.distanceText(distance, unit),
          ),
          trailing: session.fromHealth
              ? ForgeTag(
                  healthSourceName(context, session),
                  kind: ForgeTagKind.source,
                )
              : null,
          end: ListRowEnd.chevron,
          onTap: () => context.push(Routes.cardioSession(session.id!)),
        );
      case PlanEntry(:final program, :final day):
        return _PlanRow(program: program, day: day, box: box);
    }
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.program, required this.day, required this.box});

  final Program program;
  final PlannedDay day;
  final Widget box;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final programs = context.watch<ProgramListCubit>().state;
    final locked = programs.access(program) == ProgramAccess.locked;
    final missed = day.status == PlannedStatus.missed;
    final active = programs.active;
    // Only the next day has a date of its own to move.
    final movable =
        !locked &&
        active != null &&
        active.programId == program.id &&
        active.nextDayIndex == day.dayIndex &&
        (missed || active.nextDate == day.date);
    final name = l10n.dayName(program.days[day.dayIndex], day.dayIndex);
    final row = ListRow(
      leading: box,
      title: name,
      detail: missed
          ? null
          : l10n.calendarRowPlanned(program.days[day.dayIndex].items.length),
      error: missed ? l10n.calendarRowMissed : null,
      trailing: missed
          ? (locked
                ? null
                : ForgeButton(
                    label: l10n.programMissedToday,
                    size: ForgeButtonSize.small,
                    variant: ForgeButtonVariant.secondary,
                    loading: programs.resolving,
                    onPressed: () =>
                        resolveMissedDay(context, MissedDayChoice.doToday),
                  ))
          : ForgeButton(
              label: l10n.calendarStart,
              size: ForgeButtonSize.small,
              locked: locked,
              onPressed: () => startProgramDay(context, program, day.dayIndex),
            ),
    );
    if (!movable) return row;
    return GestureDetector(
      onLongPress: () => _moveSheet(context, name, active.nextDate),
      child: row,
    );
  }

  Future<void> _moveSheet(
    BuildContext context,
    String name,
    CalendarDate planned,
  ) async {
    final programs = context.read<ProgramListCubit>();
    final active = programs.state.active;
    if (active == null) return;
    final dates =
        ProgramSchedule(
          active,
          dayCount: program.days.length,
          lengthWeeks: program.lengthWeeks,
        ).moveDates(
          CalendarDate.of(DateTime.now()),
          firstWeekday: programs.firstWeekday,
        );
    final picked = await showForgeBottomSheet<CalendarDate>(
      context: context,
      builder: (_) => _MoveSheet(name: name, planned: planned, dates: dates),
    );
    if (picked == null || !context.mounted) return;
    await programs.moveNext(picked);
    final failure = programs.state.resolveFailure;
    if (failure == null || !context.mounted) return;
    final l10n = AppLocalizations.of(context);
    showForgeSnackbar(
      context,
      message: failure is NetworkFailure
          ? l10n.errorNetwork
          : l10n.programMissedFailed,
      error: true,
    );
    programs.resolveFailureShown();
  }
}

/// Picks the day of the week to move the next day to; nothing is picked
/// at first.
class _MoveSheet extends StatefulWidget {
  const _MoveSheet({
    required this.name,
    required this.planned,
    required this.dates,
  });

  final String name;
  final CalendarDate planned;
  final List<CalendarDate> dates;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  CalendarDate? _picked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final muted = ForgeStyle.of(context).colors.inkMuted;
    final picked = _picked;
    final chip = DateFormat.E(l10n.localeName);
    return ForgeBottomSheet(
      title: l10n.calendarMoveTitle(widget.name),
      action: ForgeButton(
        label: picked == null
            ? l10n.calendarMove
            : l10n.programMissedMove(l10n.weekdayLong(picked.weekday)),
        size: ForgeButtonSize.large,
        onPressed: picked == null || picked == widget.planned
            ? null
            : () => Navigator.pop(context, picked),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.md,
        children: [
          Text(
            l10n.calendarMoveMessage(l10n.planDate(widget.planned)),
            style: text.bodyMedium!.copyWith(color: muted),
          ),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final date in widget.dates)
                ForgeChip(
                  label: '${chip.format(date.toLocalDateTime())} ${date.day}',
                  selected: date == picked,
                  showCheck: false,
                  onPressed: () => setState(() => _picked = date),
                ),
            ],
          ),
          Text(
            l10n.calendarMoveNote,
            style: text.bodySmall!.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
