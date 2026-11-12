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
    required this.selected,
    required this.today,
    this.status = CalendarStatus.loading,
    this.entries = const {},
    this.failure,
  });

  /// The first day of the month shown.
  final CalendarDate month;

  /// The date whose entries are listed.
  final CalendarDate selected;
  final CalendarDate today;
  final CalendarStatus status;

  /// By date; see [calendarEntries]. Covers the dates of the month's
  /// [monthRange], so the days of the months around it shown in its first
  /// and last week have theirs too.
  final Map<CalendarDate, List<CalendarEntry>> entries;
  final Failure? failure;

  List<CalendarEntry> entriesOn(CalendarDate date) => entries[date] ?? const [];

  @override
  List<Object?> get props => [month, selected, today, status, entries, failure];
}

/// One month of the calendar of whoever is signed in: their finished
/// workouts, cardio sessions and the active program's days not done yet,
/// followed live while the month is shown. Resets on every user change.
class CalendarCubit extends Cubit<CalendarState> {
  CalendarCubit({
    required WatchAuthUser watchAuthUser,
    required this._watchWorkouts,
    required this._watchCardio,
    required this._watchPrograms,
    required this._watchActiveProgram,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(_initial(CalendarDate.of((clock ?? DateTime.now)()))) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
  }

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

  static CalendarState _initial(CalendarDate today) =>
      CalendarState(month: monthOf(today), selected: today, today: today);

  /// Shows the month [months] after the one shown, before it when negative,
  /// with today selected when it falls in it, else its first day.
  void showMonth(int months) {
    final today = _today;
    final month = addMonths(state.month, months);
    final selected = monthOf(today) == month ? today : month;
    emit(CalendarState(month: month, selected: selected, today: today));
    _followMonth();
  }

  /// Lists [date]'s entries; a date of another month also shows its month.
  void select(CalendarDate date) {
    if (monthOf(date) != state.month) {
      emit(CalendarState(month: monthOf(date), selected: date, today: _today));
      _followMonth();
      return;
    }
    emit(
      CalendarState(
        month: state.month,
        selected: date,
        today: state.today,
        status: state.status,
        entries: state.entries,
        failure: state.failure,
      ),
    );
  }

  /// Follows the month again after a failure.
  void retry() {
    emit(
      CalendarState(
        month: state.month,
        selected: state.selected,
        today: _today,
      ),
    );
    _followUser();
  }

  void _onUser(String? uid) {
    _uid = uid;
    emit(_initial(_today));
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
