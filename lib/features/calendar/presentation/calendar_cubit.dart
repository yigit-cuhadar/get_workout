import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../cardio/domain/cardio_session.dart';
import '../../cardio/domain/cardio_usecases.dart';
import '../../programs/domain/active_program.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_usecases.dart';
import '../../workout/domain/history_usecases.dart';
import '../../workout/domain/workout.dart';
import '../domain/calendar_month.dart';

enum CalendarStatus { loading, ready, failure }

class CalendarState extends Equatable {
  const CalendarState({
    required this.month,
    required this.weeks,
    required this.selected,
    required this.today,
    this.expanded = false,
    this.status = CalendarStatus.loading,
    this.entries = const {},
    this.failure,
  });

  /// The first day of the month loaded: the one shown when [expanded], else
  /// the month of the week's first day.
  final CalendarDate month;

  /// The rows shown, each seven dates: the month's (see `monthWeeks`) when
  /// [expanded], else the selected date's week.
  final List<List<CalendarDate>> weeks;

  /// The full month shows, not one week.
  final bool expanded;
  final CalendarDate selected;
  final CalendarDate today;
  final CalendarStatus status;

  /// By date; see [calendarEntries]. Covers the dates of the month's
  /// [monthRange], so every date of [weeks] has its own.
  final Map<CalendarDate, List<CalendarEntry>> entries;
  final Failure? failure;

  /// The month named above the dates: the selected date's in a week.
  CalendarDate get period => expanded ? month : monthOf(selected);

  List<CalendarEntry> entriesOn(CalendarDate date) => entries[date] ?? const [];

  @override
  List<Object?> get props => [
    month,
    weeks,
    expanded,
    selected,
    today,
    status,
    entries,
    failure,
  ];
}

/// The calendar of whoever is signed in, one week or one month at a time:
/// their finished workouts, cardio sessions and the active program's days
/// not done yet, followed live for the month loaded. [firstWeekday] (ISO)
/// starts the weeks. Resets on every user change.
class CalendarCubit extends Cubit<CalendarState> {
  CalendarCubit({
    required int firstWeekday,
    required WatchAuthUser watchAuthUser,
    required this._watchWorkouts,
    required this._watchCardio,
    required this._watchPrograms,
    required this._watchActiveProgram,
    DateTime Function()? clock,
  }) : _firstWeekday = firstWeekday,
       _clock = clock ?? DateTime.now,
       super(
         _shown(
           selected: CalendarDate.of((clock ?? DateTime.now)()),
           today: CalendarDate.of((clock ?? DateTime.now)()),
           expanded: false,
           firstWeekday: firstWeekday,
         ),
       ) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
  }

  int _firstWeekday;
  final WatchWorkoutsBetween _watchWorkouts;
  final WatchCardioBetween _watchCardio;
  final WatchPrograms _watchPrograms;
  final WatchActiveProgram _watchActiveProgram;
  final DateTime Function() _clock;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<List<Program>>? _programsSubscription;
  StreamSubscription<ActiveProgram?>? _activeSubscription;
  StreamSubscription<List<Workout>>? _workoutsSubscription;
  StreamSubscription<List<CardioSession>>? _cardioSubscription;
  String? _uid;

  /// Null until the first value arrives for the current user or month.
  List<Workout>? _workouts;
  List<CardioSession>? _cardio;
  List<Program>? _programs;
  ActiveProgram? _active;
  bool _activeKnown = false;

  CalendarDate get _today => CalendarDate.of(_clock());

  /// [selected] in a week or, [expanded], in its month, loading.
  static CalendarState _shown({
    required CalendarDate selected,
    required CalendarDate today,
    required bool expanded,
    required int firstWeekday,
  }) {
    final week = selected.startOfWeek(firstWeekday);
    final month = monthOf(expanded ? selected : week);
    return CalendarState(
      month: month,
      weeks: expanded
          ? monthWeeks(month, firstWeekday: firstWeekday)
          : [
              [for (var i = 0; i < 7; i++) week.addDays(i)],
            ],
      expanded: expanded,
      selected: selected,
      today: today,
    );
  }

  /// Shows the week or month [steps] after the one shown, before it when
  /// negative, with today selected when it falls in it, else its first day.
  void move(int steps) {
    final today = _today;
    if (state.expanded) {
      final month = addMonths(state.month, steps);
      _show(monthOf(today) == month ? today : month, expanded: true);
    } else {
      final week = state.selected.startOfWeek(_firstWeekday).addDays(7 * steps);
      _show(
        today.startOfWeek(_firstWeekday) == week ? today : week,
        expanded: false,
      );
    }
  }

  /// Starts the weeks on [firstWeekday] from now on, keeping the date
  /// selected.
  void changeFirstWeekday(int firstWeekday) {
    if (firstWeekday == _firstWeekday) return;
    _firstWeekday = firstWeekday;
    _show(state.selected, expanded: state.expanded);
  }

  /// Shows the full month of the selected date, or only its week.
  void expand(bool expanded) => _show(state.selected, expanded: expanded);

  /// Selects [date]; one of another month shows that month.
  void select(CalendarDate date) => _show(date, expanded: state.expanded);

  /// Follows the month again after a failure.
  void retry() {
    emit(_loading(state.selected, expanded: state.expanded));
    _followUser();
  }

  CalendarState _loading(CalendarDate selected, {required bool expanded}) =>
      _shown(
        selected: selected,
        today: _today,
        expanded: expanded,
        firstWeekday: _firstWeekday,
      );

  void _show(CalendarDate selected, {required bool expanded}) {
    final shown = _loading(selected, expanded: expanded);
    if (shown.month != state.month) {
      emit(shown);
      _followNewMonth();
      return;
    }
    emit(
      CalendarState(
        month: shown.month,
        weeks: shown.weeks,
        expanded: expanded,
        selected: selected,
        today: state.today,
        status: state.status,
        entries: state.entries,
        failure: state.failure,
      ),
    );
  }

  void _onUser(String? uid) {
    _uid = uid;
    emit(_loading(_today, expanded: false));
    _followUser();
  }

  void _followUser() {
    _cancelUser();
    _programs = null;
    _active = null;
    _activeKnown = false;
    final uid = _uid;
    if (uid != null) {
      // Without them the calendar still shows what was done; nothing is
      // planned.
      _programsSubscription = _watchPrograms(uid).listen(
        (programs) {
          _programs = programs;
          _emitReady();
        },
        onError: (Object error, StackTrace stack) {
          Log.e('calendar', 'programs failed', error, stack);
          _programs = const [];
          _emitReady();
        },
      );
      _activeSubscription = _watchActiveProgram(uid).listen(
        (active) {
          _active = active;
          _activeKnown = true;
          _emitReady();
        },
        onError: (Object error, StackTrace stack) {
          Log.e('calendar', 'active program failed', error, stack);
          _active = null;
          _activeKnown = true;
          _emitReady();
        },
      );
    }
    _followMonth();
  }

  /// After a failure nothing is followed any more, the user's programs
  /// included; follow those again too.
  void _followNewMonth() =>
      _programsSubscription == null ? _followUser() : _followMonth();

  void _followMonth() {
    _cancelMonth();
    _workouts = null;
    _cardio = null;
    final uid = _uid;
    if (uid == null) return;
    final (:from, :to) = monthRange(state.month);
    _workoutsSubscription = _watchWorkouts((uid: uid, from: from, to: to))
        .listen((workouts) {
          _workouts = workouts;
          _emitReady();
        }, onError: _fail);
    _cardioSubscription = _watchCardio((uid: uid, from: from, to: to))
        .listen((cardio) {
          _cardio = cardio;
          _emitReady();
        }, onError: _fail);
  }

  void _emitReady() {
    final workouts = _workouts;
    final cardio = _cardio;
    final programs = _programs;
    if (workouts == null ||
        cardio == null ||
        programs == null ||
        !_activeKnown) {
      return;
    }
    final active = _active;
    final today = _today;
    final (:from, :to) = monthRange(state.month);
    emit(
      CalendarState(
        month: state.month,
        weeks: state.weeks,
        expanded: state.expanded,
        selected: state.selected,
        today: today,
        status: CalendarStatus.ready,
        entries: calendarEntries(
          from: from,
          to: to,
          today: today,
          workouts: workouts,
          cardio: cardio,
          active: active,
          program: active == null
              ? null
              : programs.where((p) => p.id == active.programId).firstOrNull,
        ),
      ),
    );
  }

  void _fail(Object error) {
    _cancelUser();
    _cancelMonth();
    emit(
      CalendarState(
        month: state.month,
        weeks: state.weeks,
        expanded: state.expanded,
        selected: state.selected,
        today: state.today,
        status: CalendarStatus.failure,
        failure: error is Failure ? error : UnknownFailure('$error', error),
      ),
    );
  }

  void _cancelUser() {
    unawaited(_programsSubscription?.cancel());
    unawaited(_activeSubscription?.cancel());
    _programsSubscription = null;
    _activeSubscription = null;
  }

  void _cancelMonth() {
    unawaited(_workoutsSubscription?.cancel());
    unawaited(_cardioSubscription?.cancel());
    _workoutsSubscription = null;
    _cardioSubscription = null;
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    _cancelUser();
    _cancelMonth();
    return super.close();
  }
}
