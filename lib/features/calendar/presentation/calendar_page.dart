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
import '../../settings/presentation/first_weekday.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../workout/domain/exercise_stats.dart';
import '../../workout/presentation/start_workout.dart';
import '../../workout/presentation/workout_text.dart';
import '../domain/calendar_days.dart';
import '../domain/calendar_month.dart';
import 'calendar_cubit.dart';
import 'calendar_list_cubit.dart';
import 'calendar_marks.dart';
import 'month_grid.dart';

/// A week, or a month, of finished workouts, cardio and program days, above
/// everything by date, newest first.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firstWeekday = context.watchFirstWeekday();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<CalendarCubit>(param1: firstWeekday)),
        BlocProvider(
          create: (_) => sl<CalendarListCubit>(param1: firstWeekday),
        ),
      ],
      child: FirstWeekdayListener(
        created: firstWeekday,
        onChanged: (context, firstWeekday) {
          context.read<CalendarCubit>().changeFirstWeekday(firstWeekday);
          context.read<CalendarListCubit>().changeFirstWeekday(firstWeekday);
        },
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
  final _scroll = ScrollController();

  /// Each listed date's header, to scroll to.
  final _headers = <CalendarDate, GlobalKey>{};

  /// The date tapped, until the list has scrolled to it.
  CalendarDate? _pending;
  bool _seeking = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _select(CalendarDate date) {
    context.read<CalendarCubit>().select(date);
    context.read<CalendarListCubit>().reveal(date);
    _pending = date;
    _scrollToPending();
  }

  /// A move of the week or month, or of the view, selects a date the list
  /// does not scroll to.
  void _leave(void Function(CalendarCubit cubit) change) {
    change(context.read<CalendarCubit>());
    context.read<CalendarListCubit>().reveal(null);
    _pending = null;
  }

  void _scrollToPending() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _seek());

  /// Brings the pending date's header to the top. The dates are built
  /// lazily, so it may not be built yet: until it is, jumps a screen at a
  /// time towards it, past the dates built, then scrolls to it. Waits for
  /// a later state while it is not listed yet.
  Future<void> _seek() async {
    if (_seeking) return;
    _seeking = true;
    try {
      // Bounded, should the list keep changing under it.
      for (var jumps = 0; jumps < 200; jumps++) {
        if (!mounted) return;
        final pending = _pending;
        if (pending == null) return;
        final list = context.read<CalendarListCubit>().state;
        final order = [
          ?list.pinned?.date,
          for (final day in list.days) day.date,
        ];
        final index = order.indexOf(pending);
        if (index < 0) return;
        final header = _headers[pending]?.currentContext;
        if (header != null && header.mounted) {
          _pending = null;
          await Scrollable.ensureVisible(
            header,
            duration: kThemeAnimationDuration,
            curve: Curves.easeOut,
          );
          return;
        }
        final lastBuilt = order.lastIndexWhere(
          (date) => _headers[date]?.currentContext != null,
        );
        final position = _scroll.position;
        final step = position.viewportDimension;
        final target = (position.pixels + (lastBuilt < index ? step : -step))
            .clamp(position.minScrollExtent, position.maxScrollExtent);
        if (target == position.pixels) return;
        _scroll.jumpTo(target);
        await WidgetsBinding.instance.endOfFrame;
      }
    } finally {
      _seeking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocListener<CalendarListCubit, CalendarListState>(
      listenWhen: (_, current) => current.writeRejected,
      listener: (context, _) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.historyWritesRejected)));
        context.read<CalendarListCubit>().rejectionShown();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.calendarTitle),
          actions: [
            TextButton.icon(
              onPressed: () => context.go(Routes.calendarWorkoutNew),
              icon: const Icon(Icons.add),
              label: Text(l10n.calendarAddPast),
            ),
          ],
        ),
        body: BlocConsumer<CalendarListCubit, CalendarListState>(
          listener: (_, _) => _scrollToPending(),
          builder: (context, state) => CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: _PeriodCard(onSelected: _select, onMove: _leave),
              ),
              ..._list(context, state),
            ],
          ),
        ),
      ),
    );
  }

  /// Everything by date, newest first, built as it scrolls in, then the
  /// button loading older workouts.
  List<Widget> _list(BuildContext context, CalendarListState state) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<CalendarListCubit>();
    Widget fill(Widget child) =>
        SliverFillRemaining(hasScrollBody: false, child: child);
    GlobalKey header(CalendarDate date) =>
        _headers.putIfAbsent(date, GlobalKey.new);
    return switch (state.status) {
      CalendarListStatus.loading => [fill(const LoadingView())],
      CalendarListStatus.failure => [
        fill(
          ErrorView(
            message: l10n.historyLoadFailed,
            retryLabel: l10n.retry,
            onRetry: cubit.retry,
          ),
        ),
      ],
      CalendarListStatus.ready when state.isEmpty => [
        fill(
          EmptyView(
            message: l10n.historyEmpty,
            action: ForgeButton(
              label: l10n.workoutStartWorkout,
              onPressed: () => startFreeWorkout(context),
            ),
          ),
        ),
      ],
      CalendarListStatus.ready => [
        if (state.pinned case final pinned?)
          SliverToBoxAdapter(
            child: _Day(
              key: header(pinned.date),
              day: pinned,
              loading: state.pinnedLoading,
            ),
          ),
        SliverList.builder(
          itemCount: state.days.length,
          itemBuilder: (_, index) {
            final day = state.days[index];
            return _Day(key: header(day.date), day: day);
          },
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: Gap.xl),
          sliver: SliverToBoxAdapter(
            child: state.more
                ? Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: state.loadingMore
                        ? const Center(child: CircularProgressIndicator())
                        : OutlinedButton(
                            onPressed: cubit.loadMore,
                            child: Text(l10n.historyLoadOlder),
                          ),
                  )
                : null,
          ),
        ),
      ],
    };
  }
}

/// The week or month shown, with the arrows moving it and the control
/// switching between the two.
class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.onSelected, required this.onMove});

  final ValueChanged<CalendarDate> onSelected;
  final void Function(void Function(CalendarCubit cubit) change) onMove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    final state = context.watch<CalendarCubit>().state;
    final expanded = state.expanded;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: expanded
                      ? l10n.calendarPreviousMonth
                      : l10n.calendarPreviousWeek,
                  onPressed: () => onMove((cubit) => cubit.move(-1)),
                ),
                Expanded(
                  child: Text(
                    dates.formatMonthYear(state.period.toLocalDateTime()),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: expanded
                      ? l10n.calendarNextMonth
                      : l10n.calendarNextWeek,
                  onPressed: () => onMove((cubit) => cubit.move(1)),
                ),
              ],
            ),
            // While loading the dates show without marks.
            MonthGrid(
              weeks: state.weeks,
              month: expanded ? state.month : null,
              selected: state.selected,
              today: state.today,
              onSelected: onSelected,
              marks: (date) =>
                  calendarMarkIcons(context, state.entriesOn(date)),
              semanticLabel: (date) =>
                  calendarDayLabel(context, date, state.entriesOn(date)),
            ),
            if (state.status == CalendarStatus.failure)
              ErrorView(
                message: l10n.calendarLoadFailed,
                retryLabel: l10n.retry,
                onRetry: context.read<CalendarCubit>().retry,
              ),
            TextButton.icon(
              onPressed: () => onMove((cubit) => cubit.expand(!expanded)),
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(
                expanded ? l10n.calendarShowWeek : l10n.calendarShowMonth,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A date's header and its entries, or a spinner while [loading] them.
class _Day extends StatelessWidget {
  const _Day({super.key, required this.day, this.loading = false});

  final CalendarDay day;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    final today = context.select((CalendarCubit cubit) => cubit.state.today);
    final date = dates.formatFullDate(day.date.toLocalDateTime());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          title: Text(
            day.date == today ? l10n.calendarToday(date) : date,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(Gap.md),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (day.entries.isEmpty)
          ListTile(title: Text(l10n.calendarDayEmpty))
        else
          for (final entry in day.entries)
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
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final workout = entry.workout;
    final summary = summarizeWorkout(workout, const []);
    final details = [
      _time(context, workout.startedAt),
      l10n.durationMinutes(summary.duration),
      l10n.historySetCount(summary.setCount),
      if (summary.volumeKg > 0) l10n.weightText(summary.volumeKg, unit),
    ];
    return ListTile(
      leading: Icon(
        Icons.fitness_center,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(workout.name),
      subtitle: Text(details.join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(Routes.calendarWorkout(workout.id)),
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
/// ▶; a missed one is resolved in the Programs tab.
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
