import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../calendar/domain/calendar_month.dart';
import '../../cardio/domain/cardio_session.dart';
import '../../cardio/domain/cardio_usecases.dart';
import '../../programs/domain/active_program.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_usecases.dart';
import '../../workout/domain/history_usecases.dart';
import '../../workout/domain/workout.dart';

enum TodayWeekStatus { loading, ready, failure }

class TodayWeekState extends Equatable {
  const TodayWeekState({
    required this.today,
    required this.days,
    this.status = TodayWeekStatus.loading,
    this.entries = const {},
    this.failure,
  });

  final CalendarDate today;

  /// The seven dates of [today]'s week, from the locale's first weekday.
  final List<CalendarDate> days;
  final TodayWeekStatus status;

  /// By date, as the calendar has them (`calendarEntries`).
  final Map<CalendarDate, List<CalendarEntry>> entries;
  final Failure? failure;

  List<CalendarEntry> entriesOn(CalendarDate date) => entries[date] ?? const [];

  @override
  List<Object?> get props => [today, days, status, entries, failure];
}

/// The current week of whoever is signed in, as the calendar shows it:
/// workouts and cardio done, the active program's days planned or missed.
/// Weeks start on ISO weekday [firstWeekday], as the locale does. Resets
/// on every user change.
class TodayWeekCubit extends Cubit<TodayWeekState> {
  TodayWeekCubit({
    required this.firstWeekday,
    required WatchAuthUser watchAuthUser,
    required this._watchWorkouts,
    required this._watchCardio,
    required this._watchPrograms,
    required this._watchActiveProgram,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(_initial(firstWeekday, clock ?? DateTime.now)) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          _uid = uid;
          _follow();
        });
  }

  final int firstWeekday;
  final WatchWorkoutsBetween _watchWorkouts;
  final WatchCardioBetween _watchCardio;
  final WatchPrograms _watchPrograms;
  final WatchActiveProgram _watchActiveProgram;
  final DateTime Function() _clock;
  late final StreamSubscription<String?> _userSubscription;
  final _subscriptions = <StreamSubscription<Object?>>[];
  String? _uid;

  /// Null until the first value arrives for the current user and week.
  List<Workout>? _workouts;
  List<CardioSession>? _cardio;
  List<Program>? _programs;
  ActiveProgram? _active;
  bool _activeKnown = false;

  static TodayWeekState _initial(int firstWeekday, DateTime Function() clock) {
    final today = CalendarDate.of(clock());
    final start = today.startOfWeek(firstWeekday);
    return TodayWeekState(
      today: today,
      days: [for (var i = 0; i < DateTime.daysPerWeek; i++) start.addDays(i)],
    );
  }

  /// Moves to the current day, and week when it changed, e.g. after the
  /// app slept over midnight; a snapshot arriving after the week ended
  /// moves to the new week too.
  void refreshNow() {
    final now = _initial(firstWeekday, _clock);
    if (now.today == state.today) return;
    if (now.days.first != state.days.first ||
        state.status == TodayWeekStatus.failure) {
      _follow();
    } else {
      _emitReady();
    }
  }

  /// Follows the week again after a failure.
  void retry() {
    if (state.status == TodayWeekStatus.failure) _follow();
  }

  void _follow() {
    _cancel();
    _workouts = null;
    _cardio = null;
    _programs = null;
    _active = null;
    _activeKnown = false;
    final loading = _initial(firstWeekday, _clock);
    if (state != loading) emit(loading);
    final uid = _uid;
    if (uid == null) return;
    final from = loading.days.first;
    final to = loading.days.last;
    _subscriptions.addAll([
      _watchWorkouts((uid: uid, from: from, to: to)).listen((workouts) {
        _workouts = workouts;
        _emitReady();
      }, onError: _fail),
      _watchCardio((uid: uid, from: from, to: to)).listen((cardio) {
        _cardio = cardio;
        _emitReady();
      }, onError: _fail),
      // Without them the week still shows what was done; nothing is
      // planned.
      _watchPrograms(uid).listen(
        (programs) {
          _programs = programs;
          _emitReady();
        },
        onError: (Object error, StackTrace stack) {
          Log.e('today', 'programs failed', error, stack);
          _programs = const [];
          _emitReady();
        },
      ),
      _watchActiveProgram(uid).listen(
        (active) {
          _active = active;
          _activeKnown = true;
          _emitReady();
        },
        onError: (Object error, StackTrace stack) {
          Log.e('today', 'active program failed', error, stack);
          _active = null;
          _activeKnown = true;
          _emitReady();
        },
      ),
    ]);
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
    final today = CalendarDate.of(_clock());
    // The week ended since it was followed: follow the new one instead.
    if (today.startOfWeek(firstWeekday) != state.days.first) return _follow();
    final active = _active;
    final days = state.days;
    emit(
      TodayWeekState(
        today: today,
        days: days,
        status: TodayWeekStatus.ready,
        entries: calendarEntries(
          from: days.first,
          to: days.last,
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
    _cancel();
    emit(
      TodayWeekState(
        today: state.today,
        days: state.days,
        status: TodayWeekStatus.failure,
        failure: error is Failure ? error : UnknownFailure('$error', error),
      ),
    );
  }

  void _cancel() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    _cancel();
    return super.close();
  }
}
