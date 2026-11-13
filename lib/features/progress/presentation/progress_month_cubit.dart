import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../programs/domain/calendar_date.dart';
import '../domain/progress_usecases.dart';

enum ProgressMonthStatus { loading, ready, failure }

class ProgressMonthState extends Equatable {
  const ProgressMonthState({
    required this.month,
    this.status = ProgressMonthStatus.loading,
    this.workouts = 0,
    this.failure,
  });

  /// The first day of the current month.
  final CalendarDate month;
  final ProgressMonthStatus status;

  /// Finished workouts in [month], once ready.
  final int workouts;
  final Failure? failure;

  @override
  List<Object?> get props => [month, status, workouts, failure];
}

/// How many workouts whoever is signed in finished this month, followed
/// live; drops everything on a user change.
class ProgressMonthCubit extends Cubit<ProgressMonthState> {
  ProgressMonthCubit({
    required WatchAuthUser watchAuthUser,
    required this._watchCount,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(ProgressMonthState(month: _monthOf(clock ?? DateTime.now))) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          _uid = uid;
          _follow();
        });
  }

  final WatchWorkoutCountInMonth _watchCount;
  final DateTime Function() _clock;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<int>? _countSubscription;
  String? _uid;
  int _generation = 0;

  static CalendarDate _monthOf(DateTime Function() clock) {
    final now = clock();
    return CalendarDate(now.year, now.month, 1);
  }

  /// Follows the new month once the current one has ended, e.g. after the
  /// app slept over its last night.
  void refreshNow() {
    if (_monthOf(_clock) != state.month) _follow();
  }

  /// Follows the month again after a failure.
  void retry() {
    if (state.status == ProgressMonthStatus.failure) _follow();
  }

  void _follow() {
    unawaited(_countSubscription?.cancel());
    _countSubscription = null;
    final generation = ++_generation;
    final month = _monthOf(_clock);
    final loading = ProgressMonthState(month: month);
    if (state != loading) emit(loading);
    final uid = _uid;
    if (uid == null) return;
    _countSubscription = _watchCount((uid: uid, day: month)).listen(
      (count) {
        // A stream already left may still deliver.
        if (generation != _generation) return;
        emit(
          ProgressMonthState(
            month: month,
            status: ProgressMonthStatus.ready,
            workouts: count,
          ),
        );
      },
      onError: (Object error) {
        if (generation != _generation) return;
        emit(
          ProgressMonthState(
            month: month,
            status: ProgressMonthStatus.failure,
            failure: error is Failure ? error : UnknownFailure('$error', error),
          ),
        );
      },
    );
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _countSubscription?.cancel();
    return super.close();
  }
}
