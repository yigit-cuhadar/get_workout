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
import '../../workout/domain/workout_repository.dart';
import '../domain/calendar_days.dart';

enum CalendarListStatus { loading, ready, failure }

class CalendarListState extends Equatable {
  const CalendarListState({
    this.status = CalendarListStatus.loading,
    this.days = const [],
    this.more = false,
    this.loadingMore = false,
    this.failure,
    this.writeRejected = false,
  });

  final CalendarListStatus status;

  /// Newest first; see [calendarDays].
  final List<CalendarDay> days;

  /// Older workouts may follow; see [CalendarListCubit.loadMore].
  final bool more;
  final bool loadingMore;
  final Failure? failure;

  /// The server refused an edit or deletion that already looked done; tell
  /// the user, then call [CalendarListCubit.rejectionShown].
  final bool writeRejected;

  /// Nothing was ever done or is planned.
  bool get isEmpty => !more && days.every((day) => day.entries.isEmpty);

  CalendarListState copyWith({bool? writeRejected}) => CalendarListState(
    status: status,
    days: days,
    more: more,
    loadingMore: loadingMore,
    failure: failure,
    writeRejected: writeRejected ?? this.writeRejected,
  );

  @override
  List<Object?> get props => [
    status,
    days,
    more,
    loadingMore,
    failure,
    writeRejected,
  ];
}

/// One page of the history: where it starts and, once a later page is
/// loaded, where it ends.
class _Page {
  _Page({this.after});

  final HistoryCursor? after;
  HistoryCursor? through;

  /// Kept while the page is followed again with an end.
  HistoryPage? data;
  StreamSubscription<HistoryPage>? subscription;
}

/// The calendar's list of whoever is signed in, by date, newest first (see
/// [calendarDays]): from the end of this week, weeks starting on
/// [firstWeekday] (ISO), back through their finished workouts, a page at a
/// time, with their cardio sessions and the active program's days not done
/// yet in between. The first [maxLivePages] pages are followed live, so
/// edits, deletions and new workouts show at once; older ones are read
/// once. A page gets a fixed end once the next one loads, so pages never
/// skip or repeat a workout. Resets to loading on every user change.
class CalendarListCubit extends Cubit<CalendarListState> {
  CalendarListCubit({
    required this.firstWeekday,
    required WatchAuthUser watchAuthUser,
    required this._watchHistory,
    required this._watchCardio,
    required this._watchPrograms,
    required this._watchActiveProgram,
    required WatchRejectedWorkoutEdits watchRejectedEdits,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const CalendarListState()) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
    _rejectedSubscription = watchRejectedEdits().listen(
      (_) => emit(state.copyWith(writeRejected: true)),
    );
  }

  final int firstWeekday;
  final WatchHistory _watchHistory;
  final WatchCardioSessions _watchCardio;
  final WatchPrograms _watchPrograms;
  final WatchActiveProgram _watchActiveProgram;
  final DateTime Function() _clock;
  late final StreamSubscription<String?> _userSubscription;
  late final StreamSubscription<Failure> _rejectedSubscription;
  StreamSubscription<List<CardioSession>>? _cardioSubscription;
  StreamSubscription<List<Program>>? _programsSubscription;
  StreamSubscription<ActiveProgram?>? _activeSubscription;
  final _pages = <_Page>[];
  String? _uid;

  /// Null until the first value arrives for the current user.
  List<CardioSession>? _cardio;
  List<Program>? _programs;
  ActiveProgram? _active;
  bool _activeKnown = false;
  CalendarDate? _revealed;

  /// Pages followed live; a listener each.
  static const maxLivePages = 5;

  void _onUser(String? uid) {
    _uid = uid;
    _revealed = null;
    _restart();
  }

  /// Follows everything again after a failure.
  void retry() => _restart();

  void rejectionShown() => emit(state.copyWith(writeRejected: false));

  /// Lists [date] even without entries, loading older pages until the list
  /// covers it (see [listCovers]); null lists only dates with entries.
  void reveal(CalendarDate? date) {
    _revealed = date;
    _publish();
  }

  /// Loads the next older page, once the last one is full.
  void loadMore() {
    final last = _pages.lastOrNull;
    final end = last?.data?.end;
    if (last == null || end == null || !last.data!.more) return;
    last.through = end;
    _follow(last);
    _follow(_Page(after: end));
    _publish();
  }

  void _restart() {
    _stop();
    emit(CalendarListState(writeRejected: state.writeRejected));
    final uid = _uid;
    if (uid == null) return;
    _follow(_Page());
    _cardioSubscription = _watchCardio(uid).listen((cardio) {
      _cardio = cardio;
      _publish();
    }, onError: _fail);
    // Without them the list still shows what was done; nothing is planned.
    _programsSubscription = _watchPrograms(uid).listen(
      (programs) {
        _programs = programs;
        _publish();
      },
      onError: (Object error, StackTrace stack) {
        Log.e('calendar', 'programs failed', error, stack);
        _programs = const [];
        _publish();
      },
    );
    _activeSubscription = _watchActiveProgram(uid).listen(
      (active) {
        _active = active;
        _activeKnown = true;
        _publish();
      },
      onError: (Object error, StackTrace stack) {
        Log.e('calendar', 'active program failed', error, stack);
        _active = null;
        _activeKnown = true;
        _publish();
      },
    );
  }

  void _follow(_Page page) {
    final uid = _uid;
    if (uid == null) return;
    if (!_pages.contains(page)) _pages.add(page);
    final live = _pages.indexOf(page) < maxLivePages;
    unawaited(page.subscription?.cancel());
    page.subscription =
        _watchHistory((uid: uid, after: page.after, through: page.through))
            .listen((data) {
              page.data = data;
              if (!live) unawaited(page.subscription?.cancel());
              _publish();
            }, onError: _fail);
  }

  void _publish() {
    final first = _pages.firstOrNull?.data;
    final cardio = _cardio;
    final programs = _programs;
    if (first == null || cardio == null || programs == null || !_activeKnown) {
      return;
    }
    final last = _pages.last.data;
    // A workout moved to another page by an edit may briefly be in both.
    final seen = <String>{};
    final workouts = [
      for (final page in _pages)
        for (final workout in page.data?.workouts ?? const <Workout>[])
          if (seen.add(workout.id)) workout,
    ];
    // While the last page loads, it is still to come.
    final more = last?.more ?? true;
    final today = CalendarDate.of(_clock());
    final active = _active;
    emit(
      CalendarListState(
        status: CalendarListStatus.ready,
        days: calendarDays(
          today: today,
          to: today.startOfWeek(firstWeekday).addDays(6),
          workouts: workouts,
          more: more,
          cardio: cardio,
          active: active,
          program: active == null
              ? null
              : programs.where((p) => p.id == active.programId).firstOrNull,
          revealed: _revealed,
        ),
        more: more,
        loadingMore: last == null,
        writeRejected: state.writeRejected,
      ),
    );
    final revealed = _revealed;
    if (revealed != null &&
        last != null &&
        !listCovers(revealed, listFloor(workouts, more: more))) {
      loadMore();
    }
  }

  void _fail(Object error) {
    _stop();
    emit(
      CalendarListState(
        status: CalendarListStatus.failure,
        failure: error is Failure ? error : UnknownFailure('$error', error),
        writeRejected: state.writeRejected,
      ),
    );
  }

  void _stop() {
    for (final page in _pages) {
      unawaited(page.subscription?.cancel());
    }
    _pages.clear();
    unawaited(_cardioSubscription?.cancel());
    unawaited(_programsSubscription?.cancel());
    unawaited(_activeSubscription?.cancel());
    _cardioSubscription = null;
    _programsSubscription = null;
    _activeSubscription = null;
    _cardio = null;
    _programs = null;
    _active = null;
    _activeKnown = false;
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _rejectedSubscription.cancel();
    _stop();
    return super.close();
  }
}
