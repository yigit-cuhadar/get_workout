import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/history_usecases.dart';
import '../domain/workout.dart';
import '../domain/workout_repository.dart';

/// Takes note of a change the user made to a stored workout; see
/// `ActiveWorkoutCubit.storedWorkoutChanged`.
typedef StoredWorkoutChanged = void Function(
  String uid,
  String id, {
  required bool deleted,
  required Set<String> staleStats,
});

enum WorkoutDetailStatus {
  loading,
  ready,

  /// There is no such workout (any more).
  missing,
  failure,
  deleting,
  deleted,

  /// The signed-in user changed; the page closes.
  closed,
}

class WorkoutDetailState extends Equatable {
  const WorkoutDetailState({
    this.status = WorkoutDetailStatus.loading,
    this.workout,
    this.pending = false,
    this.failure,
    this.records,
  });

  final WorkoutDetailStatus status;
  final Workout? workout;

  /// The server has not confirmed the workout's latest change yet, so it
  /// cannot be edited or deleted until it does.
  final bool pending;

  /// Loading or deleting failed; after a delete, tell the user, then call
  /// [WorkoutDetailCubit.failureShown].
  final Failure? failure;

  /// The sets holding a record their exercise still keeps, as (exercise
  /// index, set index); null until read, or when they could not be.
  final Set<(int, int)>? records;

  bool get canChange => status == WorkoutDetailStatus.ready && !pending;

  WorkoutDetailState copyWith({
    WorkoutDetailStatus? status,
    Failure? Function()? failure,
    Set<(int, int)>? Function()? records,
  }) => WorkoutDetailState(
    status: status ?? this.status,
    workout: workout,
    pending: pending,
    failure: failure != null ? failure() : this.failure,
    records: records != null ? records() : this.records,
  );

  @override
  List<Object?> get props => [status, workout, pending, failure, records];
}

/// Stored workout [id] of the user signed in when it opens, followed live;
/// it can be deleted, together with the stats it fed. Closes when the
/// signed-in user changes, so it never shows another user's workout.
class WorkoutDetailCubit extends Cubit<WorkoutDetailState> {
  WorkoutDetailCubit({
    required this.id,
    required GetCurrentUser getCurrentUser,
    required WatchAuthUser watchAuthUser,
    required this._watchWorkout,
    required this._saveChange,
    required this._changed,
    required this._getRecords,
  }) : _uid = getCurrentUser()?.id,
       super(const WorkoutDetailState()) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          if (uid != _uid) {
            unawaited(_workoutSubscription?.cancel());
            emit(const WorkoutDetailState(status: WorkoutDetailStatus.closed));
          }
        });
    _follow();
  }

  final String id;
  final WatchStoredWorkout _watchWorkout;
  final SaveWorkoutChange _saveChange;
  final StoredWorkoutChanged _changed;
  final GetHeldRecords _getRecords;

  /// The user the page was opened for.
  final String? _uid;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<StoredWorkout?>? _workoutSubscription;

  /// Follows the workout again after a failure.
  void retry() {
    if (state.status == WorkoutDetailStatus.failure) _follow();
  }

  void _follow() {
    final uid = _uid;
    unawaited(_workoutSubscription?.cancel());
    if (uid == null) {
      emit(const WorkoutDetailState(status: WorkoutDetailStatus.closed));
      return;
    }
    emit(const WorkoutDetailState());
    _workoutSubscription = _watchWorkout((uid: uid, id: id)).listen(
      (stored) {
        if (!_following) return;
        if (stored == null) {
          emit(const WorkoutDetailState(status: WorkoutDetailStatus.missing));
          return;
        }
        final same = stored.workout == state.workout;
        emit(
          WorkoutDetailState(
            status: WorkoutDetailStatus.ready,
            workout: stored.workout,
            pending: stored.pending,
            records: same ? state.records : null,
          ),
        );
        if (!same) unawaited(_readRecords(uid, stored.workout));
      },
      onError: (Object error) {
        if (!_following) return;
        emit(
          WorkoutDetailState(
            status: WorkoutDetailStatus.failure,
            failure: error is Failure ? error : UnknownFailure('$error', error),
          ),
        );
      },
    );
  }

  /// The records [workout] holds, unless it changed meanwhile.
  Future<void> _readRecords(String uid, Workout workout) async {
    final result = await _getRecords((uid: uid, workout: workout));
    if (isClosed || state.workout != workout) return;
    if (result case Ok(value: final records)) {
      emit(state.copyWith(records: () => records));
    }
  }

  /// Snapshots are not shown while deleting or once closed.
  bool get _following => switch (state.status) {
    WorkoutDetailStatus.deleting ||
    WorkoutDetailStatus.deleted ||
    WorkoutDetailStatus.closed => false,
    _ => true,
  };

  /// Deletes the workout and rebuilds its exercises' stats without it.
  Future<void> delete() async {
    final uid = _uid;
    final workout = state.workout;
    if (uid == null || workout == null || !state.canChange) return;
    emit(state.copyWith(status: WorkoutDetailStatus.deleting));
    final result = await _saveChange((uid: uid, before: workout, after: null));
    if (isClosed || state.status != WorkoutDetailStatus.deleting) return;
    switch (result) {
      case Err(:final failure):
        emit(
          state.copyWith(
            status: WorkoutDetailStatus.ready,
            failure: () => failure,
          ),
        );
      case Ok(value: final stale):
        _changed(uid, id, deleted: true, staleStats: stale);
        unawaited(_workoutSubscription?.cancel());
        emit(state.copyWith(status: WorkoutDetailStatus.deleted));
    }
  }

  void failureShown() => emit(state.copyWith(failure: () => null));

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _workoutSubscription?.cancel();
    return super.close();
  }
}
