import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../../settings/domain/settings_usecases.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/exercise_stats.dart';
import '../domain/rest.dart';
import '../domain/set_logging.dart';
import '../domain/workout.dart';
import '../domain/workout_editing.dart' as editing;
import '../domain/workout_repository.dart';
import '../domain/workout_usecases.dart';
import 'workout_editor.dart';

enum WorkoutStatus {
  /// The signed-in user's workout in progress is being looked for.
  loading,

  /// No workout in progress.
  none,

  /// A workout is open; it is in progress only once it is not empty (see
  /// [ActiveWorkoutState.inProgress]).
  active,
  finishing,

  /// Stored; [ActiveWorkoutState.summary] tells how it went.
  finished,
}

/// Whether a workout started, and how many of its program day's exercises
/// were left out as no longer available.
typedef WorkoutStart = ({bool started, int skipped});

class ActiveWorkoutState extends Equatable implements EditedWorkout {
  const ActiveWorkoutState({
    this.status = WorkoutStatus.loading,
    this.workout,
    this.rest,
    this.stats = const {},
    this.invalidSet,
    this.summary,
    this.failure,
    this.restored,
    this.localUnreadable = false,
    this.savingProgram = false,
    this.savedProgramId,
  });

  final WorkoutStatus status;

  /// In progress, or once [WorkoutStatus.finished] as stored.
  @override
  final Workout? workout;

  /// The rest of the workout in progress, also once it is over (until the
  /// next one replaces it).
  final Rest? rest;

  /// The stats of the workout's exercises that have arrived; null when an
  /// exercise has none yet.
  @override
  final Map<String, ExerciseStats?> stats;

  @override
  final SetRef? invalidSet;
  final WorkoutSummary? summary;

  /// Finishing or saving as a program failed; tell the user, then call
  /// [ActiveWorkoutCubit.failureShown].
  final Failure? failure;

  /// The server refused a finished workout, now in progress again; tell
  /// the user its name, then call [ActiveWorkoutCubit.restoredShown].
  final String? restored;

  /// Workouts kept on the device could not be read and were set aside; tell
  /// the user, then call [ActiveWorkoutCubit.localUnreadableShown].
  final bool localUnreadable;
  final bool savingProgram;

  /// The program the finished workout was saved as.
  final String? savedProgramId;

  /// A workout is in progress (or being finished), so another cannot start.
  /// An empty one is not ([Workout.isEmpty]): it is not kept, shows nowhere
  /// and another simply replaces it.
  bool get inProgress =>
      (status == WorkoutStatus.active || status == WorkoutStatus.finishing) &&
      !(workout?.isEmpty ?? true);

  /// The working sets of the exercise's latest workout.
  List<WorkoutSet> _lastSets(int exercise) {
    final id = workout?.exercises.elementAtOrNull(exercise)?.exerciseId;
    return stats[id]?.last?.sets ?? const [];
  }

  @override
  WorkoutSet? lastTime(SetRef ref) => lastTimeSet(
    workout!.exercises[ref.exercise],
    ref.set,
    _lastSets(ref.exercise),
  );

  @override
  SetValues suggestion(SetRef ref) => suggestedValues(
    workout!.exercises[ref.exercise],
    ref.set,
    _lastSets(ref.exercise),
  );

  ActiveWorkoutState copyWith({
    WorkoutStatus? status,
    Workout? Function()? workout,
    Rest? Function()? rest,
    Map<String, ExerciseStats?>? stats,
    SetRef? Function()? invalidSet,
    WorkoutSummary? Function()? summary,
    Failure? Function()? failure,
    String? Function()? restored,
    bool? localUnreadable,
    bool? savingProgram,
    String? Function()? savedProgramId,
  }) => ActiveWorkoutState(
    status: status ?? this.status,
    workout: workout != null ? workout() : this.workout,
    rest: rest != null ? rest() : this.rest,
    stats: stats ?? this.stats,
    invalidSet: invalidSet != null ? invalidSet() : this.invalidSet,
    summary: summary != null ? summary() : this.summary,
    failure: failure != null ? failure() : this.failure,
    restored: restored != null ? restored() : this.restored,
    localUnreadable: localUnreadable ?? this.localUnreadable,
    savingProgram: savingProgram ?? this.savingProgram,
    savedProgramId: savedProgramId != null
        ? savedProgramId()
        : this.savedProgramId,
  );

  @override
  List<Object?> get props => [
    status,
    workout,
    rest,
    stats,
    invalidSet,
    summary,
    failure,
    restored,
    localUnreadable,
    savingProgram,
    savedProgramId,
  ];
}

/// The workout in progress of whoever is signed in, for the whole app: one
/// at a time, kept on the device after every change and brought back on the
/// next launch. On every user change it starts over with that user's own,
/// so one user's workout never shows for another.
///
/// A finished workout stays on the device until the server confirms it; one
/// the server refuses comes back as the workout in progress. Stats computed
/// from what the device knew are rebuilt from the workouts once online.
///
/// Ticking a set starts its rest under the user's rest timer settings; see
/// [_restAfterEdit]. Only this workout has rests; editing a stored one
/// does not.
class ActiveWorkoutCubit extends Cubit<ActiveWorkoutState>
    with WorkoutEditor<ActiveWorkoutState> {
  ActiveWorkoutCubit({
    required WatchAuthUser watchAuthUser,
    required this._loadLocal,
    required this._keepLocal,
    required this._newWorkoutId,
    required this._watchStats,
    required this._finishWorkout,
    required this._confirmStored,
    required this._rebuildStats,
    required this._saveAsProgram,
    required this._programs,
    required this._catalogue,
    required this._watchSettings,
    DateTime Function()? clock,
    this.retryDelay = const Duration(minutes: 1),
  }) : _clock = clock ?? DateTime.now,
       super(const ActiveWorkoutState()) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
  }

  final LoadLocalWorkouts _loadLocal;
  final KeepLocalWorkouts _keepLocal;
  final NewWorkoutId _newWorkoutId;
  final WatchExerciseStats _watchStats;
  final FinishWorkout _finishWorkout;
  final ConfirmStoredWorkout _confirmStored;
  final RebuildExerciseStats _rebuildStats;
  final SaveWorkoutAsProgram _saveAsProgram;
  final ProgramListCubit _programs;
  final ExerciseCatalogueCubit _catalogue;
  final WatchSettings _watchSettings;
  final DateTime Function() _clock;

  /// How long to wait before syncing again after the server could not be
  /// asked.
  final Duration retryDelay;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<UserSettings>? _settingsSubscription;

  /// The signed-in user's, as they arrive.
  RestTimerSettings _restTimer = const RestTimerSettings();
  final _statsSubscriptions = <String, StreamSubscription<ExerciseStats?>>{};
  String? _uid;

  /// The user [releaseUser] let go of.
  String? _released;

  /// What the device keeps for [_uid]; null until loaded, and while it
  /// cannot be read nothing is kept.
  LocalWorkouts? _local;

  /// The user a sync runs for, and whether another was asked for meanwhile.
  String? _syncing;
  bool _syncAgain = false;
  Timer? _retry;

  /// The exercise whose stats a sync is rebuilding, and whether a write to
  /// them started meanwhile: the rebuild may have read before it and
  /// written after it, so it is done again.
  String? _rebuilding;
  bool _rebuildOutdated = false;

  /// Counts finishes, whose stats writes a rebuild may have crossed.
  int _finishes = 0;

  /// How long starting a program day waits for the catalogue.
  static const catalogueWait = Duration(seconds: 10);

  @override
  Map<String, Exercise> get knownExercises => switch (_catalogue.state) {
    CatalogueReady(:final exercises) => {for (final e in exercises) e.id: e},
    _ => const {},
  };

  Future<void> _onUser(String? uid) async {
    if (uid != null) _released = null;
    _uid = uid;
    _local = null;
    _retry?.cancel();
    _stopStats();
    unawaited(_settingsSubscription?.cancel());
    _restTimer = const RestTimerSettings();
    _settingsSubscription = uid == null
        ? null
        : _watchSettings(uid).listen(
            (settings) => _restTimer = settings.restTimer,
            // The settings feature logs it; the last known ones stay.
            onError: (Object _) {},
          );
    emit(
      ActiveWorkoutState(
        status: uid == null ? WorkoutStatus.none : WorkoutStatus.loading,
      ),
    );
    if (uid == null) return;
    final result = await _loadLocal(uid);
    if (isClosed || _uid != uid || state.status != WorkoutStatus.loading) {
      return;
    }
    // Set aside by the store; what is kept from now on starts empty.
    final kept = result.valueOrNull ?? const LocalWorkouts();
    // An empty one kept by an older version is no workout in progress.
    final local = kept.draft?.isEmpty ?? false
        ? kept.copyWith(draft: () => null, rest: () => null)
        : kept;
    _local = local;
    if (result.failureOrNull case final failure?) {
      Log.e('workout', 'kept workouts unreadable: ${failure.message}');
      emit(state.copyWith(localUnreadable: true));
    }
    _emitWorkout(
      local.draft,
      status: local.draft == null ? WorkoutStatus.none : WorkoutStatus.active,
      rest: () => local.rest,
    );
    unawaited(_sync(uid));
  }

  /// Stops keeping and syncing [uid]'s workouts, as if they signed out,
  /// while their account is being deleted, so nothing of theirs is written
  /// after the server deleted it. [resumeUser] undoes it when the deletion
  /// did not happen.
  Future<void> releaseUser(String uid) async {
    if (_uid != uid) return;
    _released = uid;
    await _onUser(null);
  }

  /// Follows the user [releaseUser] let go again, unless another signed in
  /// meanwhile.
  Future<void> resumeUser() async {
    final uid = _released;
    _released = null;
    if (uid != null && _uid == null) await _onUser(uid);
  }

  /// Starts an empty workout named [name]; false while another is in
  /// progress. It is not in progress itself until an exercise is added.
  bool startFree(String name) =>
      _start((id, now) => Workout(id: id, startedAt: now, name: name));

  /// Starts an empty workout named [name] with [exercise] in it, named in
  /// [language]; false while another is in progress.
  bool startWith(Exercise exercise, String name, String language) => _start(
    (id, now) => Workout(
      id: id,
      startedAt: now,
      name: name,
      exercises: [editing.exerciseFor(exercise, language)],
    ),
  );

  /// Whether [program]'s days may be started now; see [programAccess].
  ProgramAccess access(Program program) => _programs.state.access(program);

  /// Starts day [dayIndex] of [program] with its items as goals, named
  /// [name], exercise names in [language], once the catalogue knows every
  /// item's exercise (custom ones included) and [access] is open (waiting,
  /// like for the catalogue, for a premium status that may still be on its
  /// way, e.g. right after the paywall). Items whose exercise is gone are
  /// left out and counted in [WorkoutStart.skipped]; nothing starts while
  /// another workout is in progress, the catalogue does not load, the
  /// program needs premium the user does not have, or none of the day's
  /// exercises is available.
  Future<WorkoutStart> startProgramDay(
    Program program,
    int dayIndex, {
    required String name,
    required String language,
  }) async {
    const notStarted = (started: false, skipped: 0);
    if (program.id == null || dayIndex < 0 || dayIndex >= program.days.length) {
      return notStarted;
    }
    if (access(program) != ProgramAccess.open) {
      try {
        await _programs.stream
            .firstWhere((state) => state.access(program) == ProgramAccess.open)
            .timeout(catalogueWait);
      } on Object {
        return notStarted;
      }
    }
    final ids = [
      for (final item in program.days[dayIndex].items) item.exerciseId,
    ];
    bool knowsAll(ExerciseCatalogueState state) =>
        state is CatalogueReady && ids.every(state.knows);
    if (!knowsAll(_catalogue.state)) {
      try {
        await _catalogue.stream.firstWhere(knowsAll).timeout(catalogueWait);
      } on Object {
        return notStarted;
      }
    }
    if (isClosed) return notStarted;
    final catalogue = knownExercises;
    final started = _start(
      (id, now) => editing.workoutFromProgramDay(
        id: id,
        startedAt: now,
        name: name,
        program: program,
        dayIndex: dayIndex,
        catalogue: catalogue,
        language: language,
      ),
      allowEmpty: false,
    );
    return (
      started: started,
      skipped: started
          ? ids.where((id) => !catalogue.containsKey(id)).length
          : 0,
    );
  }

  bool _start(
    Workout Function(String id, DateTime now) build, {
    bool allowEmpty = true,
  }) {
    final uid = _uid;
    final open =
        state.status == WorkoutStatus.none ||
        (state.status == WorkoutStatus.active && !state.inProgress);
    if (uid == null || _local == null || !open) return false;
    final workout = build(_newWorkoutId(uid), _clock());
    if (!allowEmpty && workout.exercises.isEmpty) return false;
    _emitWorkout(workout, status: WorkoutStatus.active);
    _keep();
    return true;
  }

  /// Ends the open workout when the user leaves it while it is empty; one
  /// in progress stays, minimized.
  Future<void> leave() async {
    if (state.status == WorkoutStatus.active && !state.inProgress) {
      await discard();
    }
  }

  /// Throws the workout in progress away.
  Future<void> discard() async {
    final uid = _uid;
    if (uid == null || state.status != WorkoutStatus.active) return;
    _emitWorkout(null, status: WorkoutStatus.none, rest: () => null);
    _keep();
    unawaited(_sync(uid));
  }

  /// Ticks the set done, its empty values taken from
  /// [ActiveWorkoutState.suggestion]; one that still lacks values stays
  /// undone and is marked as [ActiveWorkoutState.invalidSet]. A done set is
  /// unticked. Rests follow in [edit].
  @override
  void toggleDone(SetRef ref) {
    if (state.status != WorkoutStatus.active || !hasSet(ref)) return;
    final toggled = toggledSet(ref);
    if (toggled == null) {
      emit(state.copyWith(invalidSet: () => ref));
      return;
    }
    replaceSet(ref, toggled);
  }

  /// Adds [restExtension] to the running rest.
  void extendRest() {
    final rest = state.rest;
    final now = _clock();
    if (state.status != WorkoutStatus.active ||
        rest == null ||
        !rest.runsAt(now)) {
      return;
    }
    emit(state.copyWith(rest: () => rest.extendedAt(now)));
    _keep();
  }

  /// Ends the rest now.
  void skipRest() {
    if (state.status != WorkoutStatus.active || state.rest == null) return;
    emit(state.copyWith(rest: () => null));
    _keep();
  }

  /// Finishes and stores the workout; its unticked sets are left out. The
  /// program moves on with it when the programs are known now; otherwise
  /// the summary says it did not.
  Future<void> finish() async {
    final uid = _uid;
    final workout = state.workout;
    final local = _local;
    if (uid == null ||
        workout == null ||
        local == null ||
        state.status != WorkoutStatus.active) {
      return;
    }
    emit(state.copyWith(status: WorkoutStatus.finishing));
    _finishes++;
    final programs = _programs.state;
    final result = await _finishWorkout((
      uid: uid,
      workout: workout,
      program: programs.status == ProgramListStatus.ready
          ? (active: programs.active, program: programs.activeProgram)
          : null,
    ));
    if (isClosed || _uid != uid) return;
    switch (result) {
      case Err(:final failure):
        emit(
          state.copyWith(status: WorkoutStatus.active, failure: () => failure),
        );
      case Ok(:final value):
        _stopStats();
        _local = LocalWorkouts(
          finished: [
            for (final w in local.finished)
              if (w.id != value.workout.id) w,
            value.workout,
          ],
          staleStats: {...local.staleStats, ...value.staleStats},
        );
        emit(
          state.copyWith(
            status: WorkoutStatus.finished,
            rest: () => null,
            workout: () => value.workout,
            summary: () => value.summary,
            invalidSet: () => null,
          ),
        );
        _keep();
        unawaited(_sync(uid));
    }
  }

  /// Settles what the device keeps for [uid] with the server: finished
  /// workouts it confirmed are dropped, one it refused comes back as the
  /// workout in progress (once none is), then stale stats are rebuilt. Waits
  /// while offline; tries again after [retryDelay] when the server could
  /// not be asked.
  Future<void> _sync(String uid) async {
    if (_uid != uid || isClosed) return;
    if (_syncing == uid) {
      _syncAgain = true;
      return;
    }
    _syncing = uid;
    try {
      do {
        _syncAgain = false;
        if (!await _syncOnce(uid)) {
          _retry?.cancel();
          _retry = Timer(retryDelay, () => unawaited(_sync(uid)));
          return;
        }
      } while (_syncAgain && _uid == uid && !isClosed);
    } finally {
      if (_syncing == uid) _syncing = null;
    }
  }

  /// False when the server could not be asked.
  Future<bool> _syncOnce(String uid) async {
    for (final workout in [...?_local?.finished]) {
      final stored = await _confirmStored((uid: uid, id: workout.id));
      if (isClosed || _uid != uid) return true;
      // Deleted by the user meanwhile.
      if (!_local!.finished.any((w) => w.id == workout.id)) continue;
      switch (stored) {
        case Err(:final failure):
          Log.e('workout', 'workout not confirmed: ${failure.message}');
          return false;
        case Ok(value: true):
          _dropFinished(workout.id);
        case Ok(value: false):
          _restore(workout);
      }
    }
    if (_local?.finished.isNotEmpty ?? true) return true;
    for (final id in [..._local!.staleStats]) {
      final finishes = _finishes;
      _rebuilding = id;
      _rebuildOutdated = false;
      final rebuilt = await _rebuildStats((uid: uid, exerciseId: id));
      _rebuilding = null;
      if (isClosed || _uid != uid) return true;
      if (rebuilt.failureOrNull case final failure?) {
        Log.e('workout', 'stats of $id not rebuilt: ${failure.message}');
        return false;
      }
      if (_rebuildOutdated || _finishes != finishes) {
        // Still stale; the next round rebuilds it after that write.
        _syncAgain = true;
        continue;
      }
      final local = _local!;
      _local = local.copyWith(staleStats: {...local.staleStats}..remove(id));
      _keep();
    }
    return true;
  }

  void _dropFinished(String id) {
    final local = _local!;
    _local = local.copyWith(
      finished: [
        for (final w in local.finished)
          if (w.id != id) w,
      ],
    );
    _keep();
  }

  /// Brings back [workout], refused by the server, as the workout in
  /// progress, unless another is in progress or its summary is open; it is
  /// then tried again after that one.
  void _restore(Workout workout) {
    if (state.status != WorkoutStatus.none) return;
    final restored = Workout(
      id: workout.id,
      startedAt: workout.startedAt,
      programId: workout.programId,
      dayIndex: workout.dayIndex,
      name: workout.name,
      note: workout.note,
      exercises: workout.exercises,
    );
    final local = _local!;
    _local = local.copyWith(
      finished: [
        for (final w in local.finished)
          if (w.id != workout.id) w,
      ],
    );
    _emitWorkout(restored, status: WorkoutStatus.active);
    emit(state.copyWith(restored: () => workout.name));
    _keep();
  }

  /// Stores the finished free workout as a program named [name].
  Future<void> saveAsProgram(String name) async {
    final uid = _uid;
    final workout = state.workout;
    if (uid == null ||
        workout == null ||
        workout.isFromProgram ||
        state.status != WorkoutStatus.finished ||
        state.savingProgram ||
        state.savedProgramId != null) {
      return;
    }
    emit(state.copyWith(savingProgram: true));
    final result = await _saveAsProgram((
      uid: uid,
      workout: workout,
      name: name,
      catalogue: knownExercises,
    ));
    if (isClosed || _uid != uid || state.status != WorkoutStatus.finished) {
      return;
    }
    emit(
      state.copyWith(
        savingProgram: false,
        savedProgramId: () => result.valueOrNull,
        failure: () => result.failureOrNull,
      ),
    );
  }

  /// The summary was seen; the next workout can start.
  void summaryShown() {
    final uid = _uid;
    if (uid == null || state.status != WorkoutStatus.finished) return;
    emit(
      ActiveWorkoutState(
        status: WorkoutStatus.none,
        localUnreadable: state.localUnreadable,
      ),
    );
    unawaited(_sync(uid));
  }

  /// Takes note of a change user [uid] made to stored workout [id]: the
  /// stats of [staleStats] are rebuilt from the server's workouts once the
  /// finished workouts are confirmed, like those finishing computed from
  /// the cache; a rebuild of one already running is done again, as it may
  /// have read before the change and write after it. A deleted workout is no longer awaited, so a confirmation
  /// that finds it gone never brings it back.
  void storedWorkoutChanged(
    String uid,
    String id, {
    required bool deleted,
    required Set<String> staleStats,
  }) {
    final local = _local;
    if (uid != _uid || local == null) return;
    if (staleStats.contains(_rebuilding)) _rebuildOutdated = true;
    _local = local.copyWith(
      finished: [
        for (final w in local.finished)
          if (!deleted || w.id != id) w,
      ],
      staleStats: {...local.staleStats, ...staleStats},
    );
    _keep();
    unawaited(_sync(uid));
  }

  void failureShown() => emit(state.copyWith(failure: () => null));

  void restoredShown() => emit(state.copyWith(restored: () => null));

  void localUnreadableShown() => emit(state.copyWith(localUnreadable: false));

  /// Applies [change] to the workout in progress and keeps the result.
  @override
  void edit(
    Workout Function(Workout workout) change, {
    bool movesSets = false,
  }) {
    final workout = state.workout;
    if (state.status != WorkoutStatus.active || workout == null) return;
    final changed = change(workout);
    if (changed == workout) return;
    _emitWorkout(
      changed,
      status: WorkoutStatus.active,
      rest: () => _restAfterEdit(workout, changed, movesSets: movesSets),
    );
    _keep();
  }

  /// The rest once an edit made [after] of [before]: a set ticked done
  /// starts the rest [restAfterTick] gives, replacing the running one;
  /// otherwise the running one goes on, ends when the set that started it
  /// is no longer done, or forgets that set when the edit [movesSets] (see
  /// [Rest.followEdit]).
  Rest? _restAfterEdit(
    Workout before,
    Workout after, {
    required bool movesSets,
  }) {
    final ticked = movesSets ? null : newlyDone(before, after);
    if (ticked != null) {
      final catalogue = knownExercises;
      final duration = restAfterTick(
        after,
        ticked,
        settings: _restTimer,
        exerciseRestS: (id) => catalogue[id]?.defaultRestS,
      );
      if (duration != null) {
        return Rest(endsAt: _clock().add(duration), after: ticked);
      }
    }
    return state.rest?.followEdit(after, movesSets: movesSets);
  }

  void _emitWorkout(
    Workout? workout, {
    required WorkoutStatus status,
    Rest? Function()? rest,
  }) {
    emit(
      state.copyWith(
        status: status,
        workout: () => workout,
        rest: rest,
        invalidSet: () => null,
      ),
    );
    _followStats();
  }

  /// Writes what the device keeps, with the workout in progress as shown;
  /// the store writes only the latest of quick changes.
  void _keep() {
    final uid = _uid;
    final local = _local;
    if (uid == null || local == null) return;
    final draft = state.inProgress ? state.workout : null;
    final kept = local.copyWith(
      draft: () => draft,
      rest: () => draft == null ? null : state.rest,
    );
    _local = kept;
    unawaited(
      _keepLocal((uid: uid, workouts: kept)).then((result) {
        if (result.failureOrNull case final failure?) {
          Log.e('workout', 'workouts not kept: ${failure.message}');
        }
      }),
    );
  }

  /// Follows the stats of exactly the exercises of the workout in progress.
  void _followStats() {
    final uid = _uid;
    final ids = state.status == WorkoutStatus.active
        ? state.workout?.exerciseIds.toSet() ?? const <String>{}
        : const <String>{};
    for (final id in [..._statsSubscriptions.keys]) {
      if (!ids.contains(id)) {
        unawaited(_statsSubscriptions.remove(id)!.cancel());
      }
    }
    if (uid == null) return;
    for (final id in ids) {
      _statsSubscriptions[id] ??= _watchStats((uid: uid, exerciseId: id))
          .listen(
            (stats) {
              if (_uid != uid) return;
              emit(state.copyWith(stats: {...state.stats, id: stats}));
            },
            // Without them "last time" stays empty; nothing else needs them.
            onError: (Object error, StackTrace stack) =>
                Log.e('workout', 'stats of $id failed', error, stack),
          );
    }
  }

  void _stopStats() {
    for (final subscription in _statsSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _statsSubscriptions.clear();
    if (state.stats.isNotEmpty) emit(state.copyWith(stats: const {}));
  }

  @override
  Future<void> close() async {
    _retry?.cancel();
    await _userSubscription.cancel();
    await _settingsSubscription?.cancel();
    _stopStats();
    return super.close();
  }
}
