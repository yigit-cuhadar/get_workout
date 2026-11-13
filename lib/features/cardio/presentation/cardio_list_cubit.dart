import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/cardio_session.dart';
import '../domain/cardio_usecases.dart';
import '../domain/cardio_week.dart';

enum CardioListStatus { loading, ready, failure }

class CardioListState extends Equatable {
  const CardioListState({
    this.status = CardioListStatus.loading,
    this.sessions = const [],
    this.weeks = const [],
    this.chart = const [],
    this.failure,
    this.writeRejected = false,
  });

  final CardioListStatus status;

  /// Newest first.
  final List<CardioSession> sessions;

  /// [sessions] by week, newest first; only weeks with sessions.
  final List<CardioWeek> weeks;

  /// The last 12 weeks, oldest first, empty ones included.
  final List<CardioWeek> chart;
  final Failure? failure;

  /// The server refused a save or delete that already looked done; tell the
  /// user, then call [CardioListCubit.rejectionShown].
  final bool writeRejected;

  CardioListState copyWith({
    List<CardioWeek>? weeks,
    List<CardioWeek>? chart,
    bool? writeRejected,
  }) => CardioListState(
    status: status,
    sessions: sessions,
    weeks: weeks ?? this.weeks,
    chart: chart ?? this.chart,
    failure: failure,
    writeRejected: writeRejected ?? this.writeRejected,
  );

  @override
  List<Object?> get props => [
    status,
    sessions,
    weeks,
    chart,
    failure,
    writeRejected,
  ];
}

/// The cardio sessions of whoever is signed in, by week from the app's first
/// weekday (see [changeFirstWeekday]). Resets to loading on every user
/// change, so a previous user's sessions are never shown.
class CardioListCubit extends Cubit<CardioListState> {
  CardioListCubit({
    required WatchAuthUser watchAuthUser,
    required this._watchSessions,
    required WatchRejectedCardioWrites watchRejectedWrites,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const CardioListState()) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
    _rejectedSubscription = watchRejectedWrites().listen(
      (_) => emit(state.copyWith(writeRejected: true)),
    );
  }

  final WatchCardioSessions _watchSessions;
  final DateTime Function() _clock;
  late final StreamSubscription<String?> _userSubscription;
  late final StreamSubscription<Failure> _rejectedSubscription;
  StreamSubscription<List<CardioSession>>? _sessionsSubscription;
  String? _uid;

  /// One for the whole app, made without a context: Monday until the first
  /// page showing it calls [changeFirstWeekday].
  int _firstWeekday = DateTime.monday;

  void _onUser(String? uid) {
    _uid = uid;
    _follow();
  }

  /// Subscribes again after a failure.
  void retry() => _follow();

  void rejectionShown() => emit(state.copyWith(writeRejected: false));

  /// Moves the 12-week chart to the current week, e.g. after the app was in
  /// the background over the first day of a week.
  void refreshNow() {
    if (state.status != CardioListStatus.ready) return;
    emit(
      state.copyWith(
        chart: lastWeeks(state.sessions, _firstWeekday, now: _clock()),
      ),
    );
  }

  /// Starts the weeks on [firstWeekday] from now on.
  void changeFirstWeekday(int firstWeekday) {
    if (firstWeekday == _firstWeekday) return;
    _firstWeekday = firstWeekday;
    if (state.status != CardioListStatus.ready) return;
    emit(
      state.copyWith(
        weeks: groupByWeek(state.sessions, firstWeekday),
        chart: lastWeeks(state.sessions, firstWeekday, now: _clock()),
      ),
    );
  }

  void _follow() {
    unawaited(_sessionsSubscription?.cancel());
    final loading = CardioListState(writeRejected: state.writeRejected);
    if (state != loading) emit(loading);
    final uid = _uid;
    _sessionsSubscription = uid == null
        ? null
        : _watchSessions(uid).listen(
            (sessions) => emit(
              CardioListState(
                status: CardioListStatus.ready,
                sessions: sessions,
                weeks: groupByWeek(sessions, _firstWeekday),
                chart: lastWeeks(sessions, _firstWeekday, now: _clock()),
                writeRejected: state.writeRejected,
              ),
            ),
            onError: (Object error) => emit(
              CardioListState(
                status: CardioListStatus.failure,
                failure: error is Failure
                    ? error
                    : UnknownFailure('$error', error),
                writeRejected: state.writeRejected,
              ),
            ),
          );
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _rejectedSubscription.cancel();
    await _sessionsSubscription?.cancel();
    return super.close();
  }
}
