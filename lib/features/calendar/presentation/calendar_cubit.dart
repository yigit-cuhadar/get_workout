import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../cardio/domain/cardio_session.dart';
import '../../cardio/domain/cardio_usecases.dart';
import '../../cardio/domain/health_cardio.dart';
import '../../programs/domain/active_program.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_usecases.dart';
import '../../workout/domain/history_usecases.dart';
import '../../workout/domain/workout.dart';
import '../domain/calendar_days.dart';
import '../domain/calendar_month.dart';

enum CalendarStatus { loading, ready, failure }

class CalendarState extends Equatable {
  const CalendarState({
    required this.month,
    required this.weeks,
    required this.selected,
    required this.today,
    this.filter = CalendarFilter.all,
    this.status = CalendarStatus.loading,
    this.entries = const {},
    this.failure,
    this.writeRejected = false,
  });

  /// The first day of the month shown.
  final CalendarDate month;

  /// The month's rows, each seven dates (see `monthWeeks`).
  final List<List<CalendarDate>> weeks;
  final CalendarDate selected;
  final CalendarDate today;

  /// What the marks, the counts and the list show.
  final CalendarFilter filter;
  final CalendarStatus status;

  /// By date, unfiltered; see [calendarEntries]. Covers the dates of the
  /// month's [monthRange], so every date of [weeks] has its own.
  final Map<CalendarDate, List<CalendarEntry>> entries;
  final Failure? failure;

  /// The server refused an edit or deletion of a workout that already
  /// looked done; tell the user, then call [CalendarCubit.rejectionShown].
  final bool writeRejected;

  /// [date]'s entries that [filter] keeps.
  List<CalendarEntry> entriesOn(CalendarDate date) =>
      filterEntries(entries[date] ?? const [], filter);

  CalendarState copyWith({
    CalendarDate? selected,
    CalendarFilter? filter,
    bool? writeRejected,
  }) => CalendarState(
    month: month,
    weeks: weeks,
    selected: selected ?? this.selected,
    today: today,
    filter: filter ?? this.filter,
    status: status,
    entries: entries,
    failure: failure,
    writeRejected: writeRejected ?? this.writeRejected,
  );

  @override
  List<Object?> get props => [
    month,
    weeks,
    selected,
    today,
    filter,
    status,
    entries,
    failure,
    writeRejected,
  ];
}

/// The calendar of whoever is signed in, a month at a time: their finished
/// workouts, cardio sessions and the active program's days not done yet,
/// followed live for the month shown, with the health store's sessions
/// (see [GetHealthCardio]), and the workout edits the server
/// refused. [firstWeekday] (ISO) starts the weeks. Resets on every user
/// change.
class CalendarCubit extends Cubit<CalendarState> {
  CalendarCubit({
    required int firstWeekday,
    required WatchAuthUser watchAuthUser,
    required this._watchWorkouts,
    required this._watchCardio,
    required this._watchPrograms,
    required this._watchActiveProgram,
    required WatchRejectedWorkoutEdits watchRejectedEdits,
    required this._getHealth,
    DateTime Function()? clock,
  }) : _firstWeekday = firstWeekday,
       _clock = clock ?? DateTime.now,
       super(
         _shown(
           selected: CalendarDate.of((clock ?? DateTime.now)()),
           today: CalendarDate.of((clock ?? DateTime.now)()),
           firstWeekday: firstWeekday,
         ),
       ) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
    _rejectedSubscription = watchRejectedEdits().listen(
      (_) => emit(state.copyWith(writeRejected: true)),
    );
  }

  int _firstWeekday;
  final WatchWorkoutsBetween _watchWorkouts;
  final WatchCardioBetween _watchCardio;
  final WatchPrograms _watchPrograms;
  final WatchActiveProgram _watchActiveProgram;
  final GetHealthCardio _getHealth;
  final DateTime Function() _clock;
  late final StreamSubscription<String?> _userSubscription;
  late final StreamSubscription<Failure> _rejectedSubscription;
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

  /// The health store's sessions, read once per user; none until read or
  /// when they could not be.
  List<CardioSession> _health = const [];

  CalendarDate get _today => CalendarDate.of(_clock());

  /// [selected]'s month, loading.
  static CalendarState _shown({
    required CalendarDate selected,
    required CalendarDate today,
    required int firstWeekday,
    CalendarFilter filter = CalendarFilter.all,
    bool writeRejected = false,
  }) {
    final month = monthOf(selected);
    return CalendarState(
      month: month,
      weeks: monthWeeks(month, firstWeekday: firstWeekday),
      selected: selected,
      today: today,
      filter: filter,
      writeRejected: writeRejected,
    );
  }

  /// Shows the month [steps] after the one shown, before it when negative,
  /// with today selected when it falls in it, else its first day.
  void move(int steps) {
    final today = _today;
    final month = addMonths(state.month, steps);
    _show(monthOf(today) == month ? today : month);
  }

  /// Starts the weeks on [firstWeekday] from now on, keeping the date
  /// selected.
  void changeFirstWeekday(int firstWeekday) {
    if (firstWeekday == _firstWeekday) return;
    _firstWeekday = firstWeekday;
    final shown = _loading(state.selected);
    emit(
      CalendarState(
        month: shown.month,
        weeks: shown.weeks,
        selected: state.selected,
        today: state.today,
        filter: state.filter,
        status: state.status,
        entries: state.entries,
        failure: state.failure,
        writeRejected: state.writeRejected,
      ),
    );
  }

  /// Selects [date]; one of another month shows that month.
  void select(CalendarDate date) => _show(date);

  void filter(CalendarFilter filter) => emit(state.copyWith(filter: filter));

  void rejectionShown() => emit(state.copyWith(writeRejected: false));

  /// Follows the month again after a failure.
  void retry() {
    emit(_loading(state.selected));
    _followUser();
  }

  CalendarState _loading(CalendarDate selected) => _shown(
    selected: selected,
    today: _today,
    firstWeekday: _firstWeekday,
    filter: state.filter,
    writeRejected: state.writeRejected,
  );

  void _show(CalendarDate selected) {
    if (monthOf(selected) != state.month) {
      emit(_loading(selected));
      _followNewMonth();
      return;
    }
    emit(state.copyWith(selected: selected));
  }

  void _onUser(String? uid) {
    _uid = uid;
    emit(
      _shown(
        selected: _today,
        today: _today,
        firstWeekday: _firstWeekday,
        writeRejected: state.writeRejected,
      ),
    );
    _followUser();
  }

  /// A failed read leaves the calendar without them.
  Future<void> _readHealth() async {
    final uid = _uid;
    final result = await _getHealth();
    if (isClosed || uid != _uid) return;
    switch (result) {
      case Err(:final failure):
        Log.e('calendar', 'health store not read: ${failure.message}');
      case Ok(value: final health):
        _health = health;
        _emitReady();
    }
  }

  void _followUser() {
    _cancelUser();
    _health = const [];
    if (_uid != null) unawaited(_readHealth());
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
        selected: state.selected,
        today: today,
        filter: state.filter,
        status: CalendarStatus.ready,
        writeRejected: state.writeRejected,
        entries: calendarEntries(
          from: from,
          to: to,
          today: today,
          workouts: workouts,
          cardio: [...cardio, ..._health],
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
        selected: state.selected,
        today: state.today,
        filter: state.filter,
        writeRejected: state.writeRejected,
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
    await _rejectedSubscription.cancel();
    _cancelUser();
    _cancelMonth();
    return super.close();
  }
}
