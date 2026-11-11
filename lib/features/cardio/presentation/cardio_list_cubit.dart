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
  });

  final CardioListStatus status;

  /// Newest first.
  final List<CardioSession> sessions;

  /// [sessions] by week, newest first; only weeks with sessions.
  final List<CardioWeek> weeks;

  /// The last 12 weeks, oldest first, empty ones included.
  final List<CardioWeek> chart;
  final Failure? failure;

  @override
  List<Object?> get props => [status, sessions, weeks, chart, failure];
}

/// The cardio sessions of whoever is signed in. Resets to loading on every
/// user change, so a previous user's sessions are never shown.
class CardioListCubit extends Cubit<CardioListState> {
  CardioListCubit({
    required WatchAuthUser watchAuthUser,
    required this._watchSessions,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const CardioListState()) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
  }

  final WatchCardioSessions _watchSessions;
  final DateTime Function() _clock;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<List<CardioSession>>? _sessionsSubscription;
  String? _uid;

  void _onUser(String? uid) {
    _uid = uid;
    _follow();
  }

  /// Subscribes again after a failure.
  void retry() => _follow();

  void _follow() {
    unawaited(_sessionsSubscription?.cancel());
    const loading = CardioListState();
    if (state != loading) emit(loading);
    final uid = _uid;
    _sessionsSubscription = uid == null
        ? null
        : _watchSessions(uid).listen(
            (sessions) => emit(
              CardioListState(
                status: CardioListStatus.ready,
                sessions: sessions,
                weeks: groupByWeek(sessions),
                chart: lastWeeks(sessions, now: _clock()),
              ),
            ),
            onError: (Object error) => emit(
              CardioListState(
                status: CardioListStatus.failure,
                failure: error is Failure
                    ? error
                    : UnknownFailure('$error', error),
              ),
            ),
          );
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _sessionsSubscription?.cancel();
    return super.close();
  }
}
