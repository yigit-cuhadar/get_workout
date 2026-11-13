import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../domain/exercise_stats.dart';
import '../domain/history_usecases.dart';
import '../domain/set_logging.dart';
import '../domain/set_selection.dart';
import '../domain/workout.dart';
import '../domain/workout_editing.dart';
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

/// The stored workout changed while it was being edited, e.g. on another
/// device; the edits can no longer be saved over it.
enum WorkoutEditConflict { changed, deleted }

class WorkoutEditState extends Equatable implements EditedWorkout {
  const WorkoutEditState({
    this.status = WorkoutEditStatus.loading,
    this.workout,
    this.invalidSet,
    this.conflict,
    this.issue,
    this.failure,
    this.picked,
  });

  final WorkoutEditStatus status;

  /// As edited so far.
  @override
  final Workout? workout;
  @override
  final SetRef? invalidSet;

  /// While set, saving is blocked: the user reloads (when changed) or
  /// discards.
  final WorkoutEditConflict? conflict;

  /// Saving was refused; tell the user, then call
  /// [WorkoutEditCubit.problemShown].
  final WorkoutChangeIssue? issue;

  /// Loading or saving failed; after a save, tell the user, then call
  /// [WorkoutEditCubit.problemShown].
  final Failure? failure;

  @override
  final SetSelection? picked;

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
    WorkoutEditConflict? Function()? conflict,
    WorkoutChangeIssue? Function()? issue,
    Failure? Function()? failure,
    SetSelection? Function()? picked,
  }) => WorkoutEditState(
    status: status ?? this.status,
    workout: workout ?? this.workout,
    invalidSet: invalidSet != null ? invalidSet() : this.invalidSet,
    conflict: conflict != null ? conflict() : this.conflict,
    issue: issue != null ? issue() : this.issue,
    failure: failure != null ? failure() : this.failure,
    picked: picked != null ? picked() : this.picked,
  );

  @override
  List<Object?> get props => [
    status,
    workout,
    invalidSet,
    conflict,
    issue,
    failure,
    picked,
  ];
}

/// Edits stored workout [id] of the user signed in when it opens, or, with
/// no [id], a new past workout named [name]. Saving stores it with its
/// exercises' stats rebuilt and leaves the active program alone; a past
/// workout is never from a program. A stored workout can be edited once the
/// server has confirmed its latest change, and is followed while edited:
/// changed or deleted elsewhere, it is never saved over. Closes when the
/// signed-in user changes.
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

  /// The stored workout as editing started from it; what a save replaces.
  Workout? _original;

  /// The latest stored version, while it differs from [_original].
  Workout? _latest;

  /// What editing started with, to tell whether anything changed.
  Workout? _start;

  /// How long a new past workout lasts until changed.
  static const newDuration = Duration(hours: 1);

  bool get isNew => id == null;

  /// Something was edited and could still be saved.
  bool get hasChanges =>
      state.status == WorkoutEditStatus.editing &&
      state.conflict == null &&
      state.workout != _start;

  @override
  Map<String, Exercise> get knownExercises => switch (_catalogue.state) {
    CatalogueReady(:final exercises) => {for (final e in exercises) e.id: e},
    _ => const {},
  };

  /// Waits for the workout to have no unconfirmed change, edits it, and
  /// keeps following it for changes made elsewhere.
  void _follow(String uid) {
    emit(const WorkoutEditState());
    unawaited(_workoutSubscription?.cancel());
    _workoutSubscription = _watchWorkout((uid: uid, id: id!)).listen(
      (stored) {
        switch (state.status) {
          case WorkoutEditStatus.loading ||
              WorkoutEditStatus.syncing ||
              WorkoutEditStatus.missing:
            _open(stored);
          case WorkoutEditStatus.editing:
            _storedChanged(stored);
          // The save's own write, or the page is going.
          default:
        }
      },
      onError: (Object error) {
        if (state.status == WorkoutEditStatus.editing) return;
        emit(
          WorkoutEditState(
            status: WorkoutEditStatus.failure,
            failure: error is Failure ? error : UnknownFailure('$error', error),
          ),
        );
      },
    );
  }

  void _open(StoredWorkout? stored) {
    if (stored == null) {
      emit(const WorkoutEditState(status: WorkoutEditStatus.missing));
    } else if (stored.pending) {
      emit(const WorkoutEditState(status: WorkoutEditStatus.syncing));
    } else {
      _original = _start = stored.workout;
      _latest = null;
      emit(
        WorkoutEditState(
          status: WorkoutEditStatus.editing,
          workout: stored.workout,
        ),
      );
    }
  }

  void _storedChanged(StoredWorkout? stored) {
    final latest = stored?.workout;
    if (latest == _original && state.conflict == null) return;
    _latest = latest;
    emit(
      state.copyWith(
        conflict: () => latest == null
            ? WorkoutEditConflict.deleted
            : latest == _original
            ? null
            : WorkoutEditConflict.changed,
      ),
    );
  }

  /// After a [WorkoutEditConflict.changed], drops the edits and edits the
  /// latest stored version instead.
  void reload() {
    final latest = _latest;
    if (state.conflict != WorkoutEditConflict.changed || latest == null) {
      return;
    }
    _original = _start = latest;
    _latest = null;
    emit(WorkoutEditState(status: WorkoutEditStatus.editing, workout: latest));
  }

  /// Starts over after loading failed.
  void retry() {
    final uid = _uid;
    if (uid != null && state.status == WorkoutEditStatus.failure) {
      _follow(uid);
    }
  }

  @override
  bool get canEdit =>
      state.status == WorkoutEditStatus.editing && state.workout != null;

  /// Applies [change] while editing; no reference to a set is kept here,
  /// so [movesSets] does not matter.
  @override
  void edit(
    Workout Function(Workout workout) change, {
    bool movesSets = false,
    SetSelection? Function(Workout after)? select,
  }) {
    final workout = state.workout;
    if (!canEdit || workout == null) return;
    final changed = change(workout);
    if (changed == workout) return;
    emit(
      state.copyWith(
        workout: changed,
        invalidSet: () => null,
        picked: select == null ? null : () => select(changed),
      ),
    );
  }

  /// A past workout is logged as it was done.
  @override
  bool get addsWarmups => false;

  /// A new pick drops the message of a set that could not be ticked.
  @override
  void emitPicked(SetSelection? picked) =>
      emit(state.copyWith(picked: () => picked, invalidSet: () => null));

  /// Ticks the set done, its empty values taken from the sets before it;
  /// one that still lacks values stays undone and is marked as
  /// [WorkoutEditState.invalidSet].
  @override
  void toggleDone(SetRef ref) {
    if (state.status != WorkoutEditStatus.editing || !hasSet(ref)) return;
    final toggled = toggledSet(ref);
    if (toggled == null) {
      emit(state.copyWith(invalidSet: () => ref));
      return;
    }
    applyToggled(ref, toggled);
  }

  void setName(String name) => edit((workout) => workout.copyWith(name: name));

  /// Keeps the duration.
  void setStart(DateTime start) => edit(
    (workout) => workout.copyWith(
      startedAt: start,
      finishedAt: start.add(duration(workout)),
    ),
  );

  /// Cut to [WorkoutLimits.maxWorkoutDuration]; negative counts as none.
  void setTotalDuration(Duration duration) => edit(
    (workout) => workout.copyWith(
      finishedAt: workout.startedAt.add(
        duration.isNegative
            ? Duration.zero
            : duration > WorkoutLimits.maxWorkoutDuration
            ? WorkoutLimits.maxWorkoutDuration
            : duration,
      ),
    ),
  );

  /// How long [workout] lasts.
  static Duration duration(Workout workout) =>
      (workout.finishedAt ?? workout.startedAt).difference(workout.startedAt);

  /// Stores the workout, its unticked sets left out, with the stats of its
  /// exercises, before and after, rebuilt; refused while in conflict.
  Future<void> save() async {
    final uid = _uid;
    final edited = state.workout;
    if (uid == null ||
        edited == null ||
        state.status != WorkoutEditStatus.editing ||
        state.conflict != null) {
      return;
    }
    final workout = edited.copyWith(name: edited.name.trim());
    if (changeIssue(workout, _clock()) case final issue?) {
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
        // The clock moved on since the check above.
        emit(
          state.copyWith(
            status: WorkoutEditStatus.editing,
            issue: () => WorkoutChangeIssue.invalid,
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
        unawaited(_workoutSubscription?.cancel());
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
