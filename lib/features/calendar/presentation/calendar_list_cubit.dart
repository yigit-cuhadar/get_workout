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
    this.pinned,
    this.pinnedLoading = false,
    this.more = false,
    this.loadingMore = false,
    this.failure,
    this.writeRejected = false,
  });

  final CalendarListStatus status;

  /// Newest first; see [calendarDays].
  final List<CalendarDay> days;

  /// A date asked for that [days] does not show, on its own above them;
  /// see [calendarDay]. Without entries while [pinnedLoading].
  final CalendarDay? pinned;
  final bool pinnedLoading;

  /// Older workouts may follow; see [CalendarListCubit.loadMore].
  final bool more;
  final bool loadingMore;
  final Failure? failure;

  /// The server refused an edit or deletion that already looked done; tell
  /// the user, then call [CalendarListCubit.rejectionShown].
  final bool writeRejected;

  /// Nothing to list: nothing was done or is planned.
  bool get isEmpty =>
      !more &&
      days.every((day) => day.entries.isEmpty) &&
      (pinned?.entries.isEmpty ?? true);

  CalendarListState copyWith({bool? writeRejected}) => CalendarListState(
    status: status,
    days: days,
    pinned: pinned,
    pinnedLoading: pinnedLoading,
    more: more,
    loadingMore: loadingMore,
    failure: failure,
    writeRejected: writeRejected ?? this.writeRejected,
  );

  @override
  List<Object?> get props => [
    status,
    days,
    pinned,
    pinnedLoading,
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

/// The cardio sessions of the dates from [from] to [to].
class _CardioRange {
  _CardioRange(this.from, this.to);

  final CalendarDate from;
  final CalendarDate to;
  List<CardioSession>? data;
  StreamSubscription<List<CardioSession>>? subscription;
}

/// The calendar's list of whoever is signed in (see [calendarDays]): from
/// the end of this week, weeks starting on [firstWeekday] (ISO), back
/// through their finished workouts, a page at a time, with their cardio
/// sessions and the active program's days not done yet on the dates those
/// cover. The first [maxLivePages] pages are followed live, so edits,
/// deletions and new workouts show at once; older ones are read once. A
/// page gets a fixed end once the next one loads, so pages never skip or
/// repeat a workout. Cardio is read for the dates listed, each once. A date
/// asked for outside them is read on its own. Resets to loading on every
/// user change.
class CalendarListCubit extends Cubit<CalendarListState> {
  CalendarListCubit({
    required this._firstWeekday,
    required WatchAuthUser watchAuthUser,
    required this._watchHistory,
    required this._watchWorkouts,
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

  int _firstWeekday;
  final WatchHistory _watchHistory;
  final WatchWorkoutsBetween _watchWorkouts;
  final WatchCardioBetween _watchCardio;
  final WatchPrograms _watchPrograms;
  final WatchActiveProgram _watchActiveProgram;
  final DateTime Function() _clock;
  late final StreamSubscription<String?> _userSubscription;
  late final StreamSubscription<Failure> _rejectedSubscription;
  StreamSubscription<List<Program>>? _programsSubscription;
  StreamSubscription<ActiveProgram?>? _activeSubscription;
  final _pages = <_Page>[];

  /// Each older than the one before, together the dates listed and more.
  final _cardio = <_CardioRange>[];
  String? _uid;

  /// Null until the first value arrives for the current user.
  List<Program>? _programs;
  ActiveProgram? _active;
  bool _activeKnown = false;
  CalendarDate? _revealed;

  /// The revealed date, while the list does not show it.
  CalendarDate? _pinnedDate;
  List<Workout>? _pinnedWorkouts;
  List<CardioSession>? _pinnedCardio;
  StreamSubscription<List<Workout>>? _pinnedWorkoutsSubscription;
  StreamSubscription<List<CardioSession>>? _pinnedCardioSubscription;

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

  /// Lists [date] even without entries: in place when the list shows it,
  /// else on its own above it; null lists only dates with entries.
  void reveal(CalendarDate? date) {
    _revealed = date;
    _publish();
  }

  /// Starts the weeks on [firstWeekday] from now on: the list ends with
  /// another date, so it is read again.
  void changeFirstWeekday(int firstWeekday) {
    if (firstWeekday == _firstWeekday) return;
    _firstWeekday = firstWeekday;
    _restart();
  }

  /// Loads the next older page, once the last one is full.
  void loadMore() {
    final last = _pages.lastOrNull;
    final end = last?.data?.end;
    if (last == null || end == null || !last.data!.more) return;
    last.through = end;
    // A page read once already has its end; only a live one is followed
    // again with it.
    if (last.subscription != null) _follow(last);
    _follow(_Page(after: end));
    _publish();
  }

  void _restart() {
    _stop();
    emit(CalendarListState(writeRejected: state.writeRejected));
    final uid = _uid;
    if (uid == null) return;
    _follow(_Page());
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
              if (!live) {
                unawaited(page.subscription?.cancel());
                page.subscription = null;
              }
              _publish();
            }, onError: _fail);
  }

  /// Reads the cardio of the dates from [from] to [to] not read yet.
  void _readCardio(String uid, CalendarDate from, CalendarDate to) {
    final oldest = _cardio.lastOrNull?.from;
    if (oldest != null && !from.isBefore(oldest)) return;
    final range = _CardioRange(from, oldest?.addDays(-1) ?? to);
    _cardio.add(range);
    range.subscription =
        _watchCardio((uid: uid, from: range.from, to: range.to))
            .listen((cardio) {
              range.data = cardio;
              _publish();
            }, onError: _fail);
  }

  /// Reads [date] on its own, or stops when null.
  void _pin(String uid, CalendarDate? date) {
    if (date == _pinnedDate) return;
    _unpin();
    _pinnedDate = date;
    if (date == null) return;
    final range = (uid: uid, from: date, to: date);
    _pinnedWorkoutsSubscription = _watchWorkouts(range).listen((workouts) {
      _pinnedWorkouts = workouts;
      _publish();
    }, onError: _fail);
    _pinnedCardioSubscription = _watchCardio(range).listen((cardio) {
      _pinnedCardio = cardio;
      _publish();
    }, onError: _fail);
  }

  void _publish() {
    final uid = _uid;
    final first = _pages.firstOrNull?.data;
    final programs = _programs;
    if (uid == null || first == null || programs == null || !_activeKnown) {
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
    final weekStart = today.startOfWeek(_firstWeekday);
    final end = weekStart.addDays(6);
    final start = listStart(workouts, more: more, weekStart: weekStart);
    _readCardio(uid, start, end);
    if (_cardio.first.data == null) return;

    final revealed = _revealed;
    _pin(
      uid,
      revealed == null ||
              listShows(revealed, start: start, end: end, more: more)
          ? null
          : revealed,
    );
    final pinnedDate = _pinnedDate;
    final pinnedWorkouts = _pinnedWorkouts;
    final pinnedCardio = _pinnedCardio;
    final pinnedLoading =
        pinnedDate != null && (pinnedWorkouts == null || pinnedCardio == null);

    final active = _active;
    final program = active == null
        ? null
        : programs.where((p) => p.id == active.programId).firstOrNull;
    emit(
      CalendarListState(
        status: CalendarListStatus.ready,
        days: calendarDays(
          today: today,
          start: start,
          end: end,
          workouts: workouts,
          more: more,
          cardio: [for (final range in _cardio) ...?range.data],
          active: active,
          program: program,
          revealed: revealed,
        ),
        pinned: pinnedDate == null
            ? null
            : pinnedLoading
            ? CalendarDay(pinnedDate, const [])
            : calendarDay(
                pinnedDate,
                today: today,
                workouts: pinnedWorkouts!,
                cardio: pinnedCardio!,
                active: active,
                program: program,
              ),
        pinnedLoading: pinnedLoading,
        more: more,
        loadingMore: last == null || _cardio.any((range) => range.data == null),
        writeRejected: state.writeRejected,
      ),
    );
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

  void _unpin() {
    unawaited(_pinnedWorkoutsSubscription?.cancel());
    unawaited(_pinnedCardioSubscription?.cancel());
    _pinnedWorkoutsSubscription = null;
    _pinnedCardioSubscription = null;
    _pinnedDate = null;
    _pinnedWorkouts = null;
    _pinnedCardio = null;
  }

  void _stop() {
    for (final page in _pages) {
      unawaited(page.subscription?.cancel());
    }
    _pages.clear();
    for (final range in _cardio) {
      unawaited(range.subscription?.cancel());
    }
    _cardio.clear();
    _unpin();
    unawaited(_programsSubscription?.cancel());
    unawaited(_activeSubscription?.cancel());
    _programsSubscription = null;
    _activeSubscription = null;
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
