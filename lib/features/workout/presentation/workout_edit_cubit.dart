import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../domain/exercise_stats.dart';
import '../domain/history_usecases.dart';
import '../domain/set_logging.dart';
import '../domain/workout.dart';
import '../domain/workout_repository.dart';
import '../domain/workout_usecases.dart';
import 'workout_detail_cubit.dart';
import 'workout_editor.dart';

enum WorkoutEditStatus {
  loading,

  /// There is no such workout (any more).
  missing,

  /// The server has not confirmed the workout's latest change yet; editing
  /// starts once it does.
  syncing,
  failure,
  editing,
  saving,
  saved,

  /// The signed-in user changed; the page closes.
  closed,
}

/// Why a save was refused before it started.
enum WorkoutEditIssue { noDoneSet, startInFuture, invalid }

class WorkoutEditState extends Equatable implements EditedWorkout {
  const WorkoutEditState({
    this.status = WorkoutEditStatus.loading,
    this.workout,
    this.invalidSet,
    this.issue,
    this.failure,
  });

  final WorkoutEditStatus status;

  /// As edited so far.
  @override
  final Workout? workout;
  @override
  final SetRef? invalidSet;

  /// Tell the user, then call [WorkoutEditCubit.problemShown].
  final WorkoutEditIssue? issue;

  /// Loading or saving failed; after a save, tell the user, then call
  /// [WorkoutEditCubit.problemShown].
  final Failure? failure;

  /// A stored workout has nothing to compare with, so no last time is shown.
  @override
  Map<String, ExerciseStats?> get stats => const {};

  @override
  WorkoutSet? lastTime(SetRef ref) => null;

  @override
  SetValues suggestion(SetRef ref) =>
      suggestedValues(workout!.exercises[ref.exercise], ref.set, const []);

  WorkoutEditState copyWith({
    WorkoutEditStatus? status,
    Workout? workout,
    SetRef? Function()? invalidSet,
    WorkoutEditIssue? Function()? issue,
    Failure? Function()? failure,
  }) => WorkoutEditState(
    status: status ?? this.status,
    workout: workout ?? this.workout,
    invalidSet: invalidSet != null ? invalidSet() : this.invalidSet,
    issue: issue != null ? issue() : this.issue,
    failure: failure != null ? failure() : this.failure,
  );

  @override
  List<Object?> get props => [status, workout, invalidSet, issue, failure];
}

/// Edits stored workout [id] of the user signed in when it opens, or, with
/// no [id], a new past workout named [name]. Saving stores it with its
/// exercises' stats rebuilt and leaves the active program alone; a past
/// workout is never from a program. A stored workout can be edited once the
/// server has confirmed its latest change. Closes when the signed-in user
/// changes.
class WorkoutEditCubit extends Cubit<WorkoutEditState>
    with WorkoutEditor<WorkoutEditState> {
  WorkoutEditCubit({
    this.id,
    required String name,
    required GetCurrentUser getCurrentUser,
    required WatchAuthUser watchAuthUser,
    required this._watchWorkout,
    required NewWorkoutId newWorkoutId,
    required this._saveChange,
    required this._changed,
    required this._catalogue,
    DateTime Function()? clock,
  }) : _uid = getCurrentUser()?.id,
       _clock = clock ?? DateTime.now,
       super(const WorkoutEditState()) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          if (uid != _uid) _close();
        });
    final uid = _uid;
    if (uid == null) {
      _close();
    } else if (id == null) {
      final now = _clock();
      final start = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
      ).subtract(newDuration);
      _start = Workout(
        id: newWorkoutId(uid),
        startedAt: start,
        finishedAt: start.add(newDuration),
        name: name,
      );
      emit(
        WorkoutEditState(status: WorkoutEditStatus.editing, workout: _start),
      );
    } else {
      _follow(uid);
    }
  }

  /// Null for a new past workout.
  final String? id;
  final WatchStoredWorkout _watchWorkout;
  final SaveWorkoutChange _saveChange;
  final StoredWorkoutChanged _changed;
  final ExerciseCatalogueCubit _catalogue;
  final DateTime Function() _clock;

  /// The user the page was opened for.
  final String? _uid;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<StoredWorkout?>? _workoutSubscription;

  /// The stored workout as it was when editing started.
  Workout? _original;

  /// What editing started with, to tell whether anything changed.
  Workout? _start;

  /// How long a new past workout lasts until changed.
  static const newDuration = Duration(hours: 1);

  /// The longest a workout can be set to last.
  static const maxDuration = Duration(hours: 24);

  bool get isNew => id == null;

  /// Something was edited and not saved yet.
  bool get hasChanges =>
      state.status == WorkoutEditStatus.editing && state.workout != _start;

  @override
  Map<String, Exercise> get knownExercises => switch (_catalogue.state) {
    CatalogueReady(:final exercises) => {for (final e in exercises) e.id: e},
    _ => const {},
  };

  /// Waits for the workout to have no unconfirmed change, then edits it.
  void _follow(String uid) {
    emit(const WorkoutEditState());
    _workoutSubscription = _watchWorkout((uid: uid, id: id!)).listen(
      (stored) {
        if (stored == null) {
          emit(const WorkoutEditState(status: WorkoutEditStatus.missing));
        } else if (stored.pending) {
          emit(const WorkoutEditState(status: WorkoutEditStatus.syncing));
        } else {
          unawaited(_workoutSubscription?.cancel());
          _original = stored.workout;
          _start = stored.workout;
          emit(
            WorkoutEditState(
              status: WorkoutEditStatus.editing,
              workout: stored.workout,
            ),
          );
        }
      },
      onError: (Object error) => emit(
        WorkoutEditState(
          status: WorkoutEditStatus.failure,
          failure: error is Failure ? error : UnknownFailure('$error', error),
        ),
      ),
    );
  }

  /// Starts over after loading failed.
  void retry() {
    final uid = _uid;
    if (uid != null && state.status == WorkoutEditStatus.failure) {
      _follow(uid);
    }
  }

  /// Applies [change] while editing.
  @override
  void edit(Workout Function(Workout workout) change) {
    final workout = state.workout;
    if (state.status != WorkoutEditStatus.editing || workout == null) return;
    final changed = change(workout);
    if (changed == workout) return;
    emit(state.copyWith(workout: changed, invalidSet: () => null));
  }

  /// Ticks the set done, its empty values taken from the sets before it;
  /// one that still lacks values stays undone and is marked as
  /// [WorkoutEditState.invalidSet].
  @override
  void toggleDone(SetRef ref) {
    if (state.status != WorkoutEditStatus.editing) return;
    final toggled = toggledSet(ref);
    if (toggled == null) {
      emit(state.copyWith(invalidSet: () => ref));
      return;
    }
    replaceSet(ref, toggled);
  }

  void setName(String name) => edit((workout) => workout.copyWith(name: name));

  /// Keeps the duration.
  void setStart(DateTime start) => edit(
    (workout) => workout.copyWith(
      startedAt: start,
      finishedAt: start.add(_duration(workout)),
    ),
  );

  /// Cut to [maxDuration]; negative counts as none.
  void setTotalDuration(Duration duration) => edit(
    (workout) => workout.copyWith(
      finishedAt: workout.startedAt.add(
        duration.isNegative
            ? Duration.zero
            : duration > maxDuration
            ? maxDuration
            : duration,
      ),
    ),
  );

  static Duration _duration(Workout workout) =>
      (workout.finishedAt ?? workout.startedAt).difference(workout.startedAt);

  /// Stores the workout, its unticked sets left out, with the stats of its
  /// exercises, before and after, rebuilt.
  Future<void> save() async {
    final uid = _uid;
    final edited = state.workout;
    if (uid == null ||
        edited == null ||
        state.status != WorkoutEditStatus.editing) {
      return;
    }
    final workout = edited.copyWith(name: edited.name.trim());
    final issue = workout.doneSetCount == 0
        ? WorkoutEditIssue.noDoneSet
        : workout.startedAt.isAfter(_clock())
        ? WorkoutEditIssue.startInFuture
        : null;
    if (issue != null) {
      emit(state.copyWith(issue: () => issue));
      return;
    }
    emit(state.copyWith(status: WorkoutEditStatus.saving));
    final result = await _saveChange((
      uid: uid,
      before: _original,
      after: workout,
    ));
    if (isClosed || state.status != WorkoutEditStatus.saving) return;
    switch (result) {
      case Err(failure: ValidationFailure()):
        emit(
          state.copyWith(
            status: WorkoutEditStatus.editing,
            issue: () => WorkoutEditIssue.invalid,
          ),
        );
      case Err(:final failure):
        emit(
          state.copyWith(
            status: WorkoutEditStatus.editing,
            failure: () => failure,
          ),
        );
      case Ok(value: final stale):
        _changed(uid, workout.id, deleted: false, staleStats: stale);
        emit(state.copyWith(status: WorkoutEditStatus.saved));
    }
  }

  void problemShown() =>
      emit(state.copyWith(issue: () => null, failure: () => null));

  void _close() {
    unawaited(_workoutSubscription?.cancel());
    emit(const WorkoutEditState(status: WorkoutEditStatus.closed));
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _workoutSubscription?.cancel();
    return super.close();
  }
}
