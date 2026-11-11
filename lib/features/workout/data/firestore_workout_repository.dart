import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../../programs/data/firestore_program_repository.dart';
import '../../programs/domain/active_program.dart';
import '../domain/exercise_stats.dart';
import '../domain/workout.dart';
import '../domain/workout_repository.dart';
import 'workout_maps.dart';

/// Workouts live in `users/{uid}/workouts/{id}`, stats in
/// `users/{uid}/exerciseStats/{exerciseId}`, the active program in the
/// `activeProgram` map of `users/{uid}`. `FirestoreCollection` is not used:
/// a workout, its stats and the program go in one batch, and a bad document
/// must not fail a whole stream.
class FirestoreWorkoutRepository implements WorkoutRepository {
  FirestoreWorkoutRepository(
    this._firestore, {
    Future<void> Function()? waitForPendingWrites,
  }) : _waitForPendingWrites =
           waitForPendingWrites ?? _firestore.waitForPendingWrites;

  final FirebaseFirestore _firestore;
  final Future<void> Function() _waitForPendingWrites;
  final _rejectedEdits = StreamController<Failure>.broadcast();

  /// The commit of each [saveWorkout] since the app started, by user and
  /// workout, until [isStored] has its answer.
  final _commits = <String, Future<void>>{};

  /// How long finishing waits for the server's stats, all of them
  /// together, before taking the cache's.
  static const serverWait = Duration(seconds: 2);

  /// The most workouts of one exercise a rebuild reads, years of training;
  /// beyond it the stats are left as they are.
  static const maxRebuildWorkouts = 500;

  /// Workouts per history page without an end.
  static const historyPageSize = 20;

  @override
  String newWorkoutId(String uid) => _workouts(uid).doc().id;

  @override
  Stream<ExerciseStats?> watchStats(String uid, String exerciseId) =>
      _stats(uid)
          .doc(exerciseId)
          .snapshots()
          .map((snap) => statsFromMap(snap.data()))
          .transform(_failures());

  @override
  Stream<HistoryPage> watchHistory(
    String uid, {
    HistoryCursor? after,
    HistoryCursor? through,
  }) {
    var query = _workouts(uid).orderBy('startedAt', descending: true);
    if (after != null) query = query.startAfterDocument(_position(after));
    query = through == null
        ? query.limit(historyPageSize)
        : query.endAtDocument(_position(through));
    return query
        .snapshots()
        .map(
          (snap) => (
            workouts: [
              for (final doc in snap.docs) ?workoutFromMap(doc.id, doc.data()),
            ],
            end: snap.docs.isEmpty ? null : HistoryCursor(snap.docs.last),
            more: through == null && snap.docs.length == historyPageSize,
          ),
        )
        .transform(_failures());
  }

  static DocumentSnapshot<Map<String, dynamic>> _position(
    HistoryCursor cursor,
  ) => cursor.position as DocumentSnapshot<Map<String, dynamic>>;

  @override
  Stream<StoredWorkout?> watchWorkout(String uid, String id) =>
      _workouts(uid)
          .doc(id)
          .snapshots(includeMetadataChanges: true)
          .map((snap) {
            final data = snap.data();
            final workout = data == null ? null : workoutFromMap(id, data);
            return workout == null
                ? null
                : (workout: workout, pending: snap.metadata.hasPendingWrites);
          })
          .transform(_failures());

  /// Stream errors as [Failure]s, logged.
  static StreamTransformer<T, T> _failures<T>() =>
      StreamTransformer.fromHandlers(
        handleError: (error, stack, sink) {
          final failure =
              mapFirebaseError(error) ?? UnknownFailure('$error', error);
          Log.e('workout', failure.message, error, stack);
          sink.addError(failure, stack);
        },
      );

  @override
  Future<Result<Map<String, StatsRead>>> getStats(
    String uid,
    List<String> exerciseIds,
  ) => guard(() async {
    final docs = [for (final id in exerciseIds) _stats(uid).doc(id)];
    final server = await _fromServer(docs);
    final stats = <String, StatsRead>{};
    for (final (i, doc) in docs.indexed) {
      final snap = server?[i] ?? await _fromCache(doc);
      if (snap != null) {
        stats[doc.id] = (
          stats: statsFromMap(snap.data()),
          current: !snap.metadata.isFromCache,
        );
      }
    }
    return stats;
  }, mapper: mapFirebaseError);

  /// All of [docs] read together, when they all arrive within [serverWait];
  /// null otherwise, e.g. offline.
  static Future<List<DocumentSnapshot<Map<String, dynamic>>>?> _fromServer(
    List<DocumentReference<Map<String, dynamic>>> docs,
  ) async {
    try {
      return await Future.wait([for (final doc in docs) doc.get()])
          .timeout(serverWait);
    } on Object {
      return null;
    }
  }

  /// Null when [doc] was never loaded on this device.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> _fromCache(
    DocumentReference<Map<String, dynamic>> doc,
  ) async {
    try {
      return await doc.get(const GetOptions(source: Source.cache));
    } on FirebaseException catch (error, stack) {
      Log.e('workout', 'stats ${doc.id} unreadable', error, stack);
      return null;
    }
  }

  @override
  Future<Result<void>> saveWorkout(
    String uid,
    Workout workout,
    Map<String, ExerciseStats> stats, {
    ActiveProgram? advance,
  }) => guard(() async {
    final batch = _firestore.batch()
      ..set(_workouts(uid).doc(workout.id), workoutToMap(workout));
    for (final MapEntry(key: id, value: value) in stats.entries) {
      batch.set(_stats(uid).doc(id), statsToMap(value));
    }
    if (advance != null) {
      batch.set(_firestore.collection('users').doc(uid), {
        'activeProgram': FirestoreProgramRepository.activeToMap(advance),
      }, SetOptions(merge: true));
    }
    final commit = batch.commit();
    _commits['$uid/${workout.id}'] = commit;
    _logRejection(commit);
  }, mapper: mapFirebaseError);

  @override
  Future<Result<bool>> isStored(String uid, String id) => guard(() async {
    // The batch's own answer tells a refusal from a later deletion.
    if (_commits.remove('$uid/$id') case final commit?) {
      try {
        await commit;
        return true;
      } on Object {
        return false;
      }
    }
    await _waitForPendingWrites();
    final doc = await _workouts(uid)
        .doc(id)
        .get(const GetOptions(source: Source.server));
    return doc.exists;
  }, mapper: mapFirebaseError);

  @override
  Future<Result<ExerciseWorkouts>> workoutsWith(
    String uid,
    String exerciseId,
  ) => guard(() async {
    // A pending edit would otherwise be missed, and its stats overwritten.
    // Offline this waits until the device is online again.
    await _waitForPendingWrites();
    return _exerciseWorkouts(
      await _doing(
        uid,
        exerciseId,
      ).get(const GetOptions(source: Source.server)),
    );
  }, mapper: mapFirebaseError);

  @override
  Future<Result<WorkoutsByExercise>> workoutsDoing(
    String uid,
    List<String> exerciseIds,
  ) => guard(() async {
    final queries = [for (final id in exerciseIds) _doing(uid, id)];
    Future<List<QuerySnapshot<Map<String, dynamic>>>> read(Source source) =>
        Future.wait([
          for (final q in queries) q.get(GetOptions(source: source)),
        ]);
    List<QuerySnapshot<Map<String, dynamic>>> snaps;
    var current = true;
    try {
      snaps = await () async {
        await _waitForPendingWrites();
        return read(Source.server);
      }().timeout(serverWait);
    } on Object {
      current = false;
      snaps = await read(Source.cache);
    }
    return (
      workouts: {
        for (final (i, id) in exerciseIds.indexed)
          id: _exerciseWorkouts(snaps[i]),
      },
      current: current,
    );
  }, mapper: mapFirebaseError);

  Query<Map<String, dynamic>> _doing(String uid, String exerciseId) =>
      _workouts(uid)
          .where('exerciseIds', arrayContains: exerciseId)
          .limit(maxRebuildWorkouts);

  static ExerciseWorkouts _exerciseWorkouts(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) => (
    workouts: [
      for (final doc in snap.docs) ?workoutFromMap(doc.id, doc.data()),
    ],
    complete: snap.docs.length < maxRebuildWorkouts,
  );

  @override
  Future<Result<void>> saveStats(
    String uid,
    String exerciseId,
    ExerciseStats? stats,
  ) => guard(() async {
    final doc = _stats(uid).doc(exerciseId);
    _logRejection(stats == null ? doc.delete() : doc.set(statsToMap(stats)));
  }, mapper: mapFirebaseError);

  @override
  Future<Result<void>> updateWorkout(
    String uid,
    Workout workout,
    Map<String, ExerciseStats?> stats,
  ) => guard(() async {
    _commitEdit(
      _withStats(uid, stats)
        ..set(_workouts(uid).doc(workout.id), workoutToMap(workout)),
    );
  }, mapper: mapFirebaseError);

  @override
  Future<Result<void>> deleteWorkout(
    String uid,
    String id,
    Map<String, ExerciseStats?> stats,
  ) => guard(() async {
    _commitEdit(_withStats(uid, stats)..delete(_workouts(uid).doc(id)));
  }, mapper: mapFirebaseError);

  @override
  Stream<Failure> get rejectedEdits => _rejectedEdits.stream;

  WriteBatch _withStats(String uid, Map<String, ExerciseStats?> stats) {
    final batch = _firestore.batch();
    for (final MapEntry(key: id, :value) in stats.entries) {
      final doc = _stats(uid).doc(id);
      value == null ? batch.delete(doc) : batch.set(doc, statsToMap(value));
    }
    return batch;
  }

  /// Like [_logRejection], and a refusal is reported on [rejectedEdits].
  void _commitEdit(WriteBatch batch) => unawaited(
    batch.commit().then(
      (_) {},
      onError: (Object error, StackTrace stack) {
        final failure =
            mapFirebaseError(error) ?? UnknownFailure('$error', error);
        Log.e('workout', 'edit rejected: ${failure.message}', error, stack);
        _rejectedEdits.add(failure);
      },
    ),
  );

  /// Firestore applies a write to its cache at once but completes it only
  /// when the server confirms, which never happens offline, so callers do
  /// not wait for that; [isStored] finds out what happened to a workout.
  static void _logRejection(Future<void> write) => unawaited(
    write.then(
      (_) {},
      onError: (Object error, StackTrace stack) =>
          Log.e('workout', 'write rejected', error, stack),
    ),
  );

  CollectionReference<Map<String, dynamic>> _workouts(String uid) =>
      _firestore.collection('users/$uid/workouts');

  CollectionReference<Map<String, dynamic>> _stats(String uid) =>
      _firestore.collection('users/$uid/exerciseStats');

  /// A finished workout's document. Missing values are left out.
  static Map<String, Object?> workoutToMap(Workout workout) => {
    'startedAt': Timestamp.fromDate(workout.startedAt),
    'finishedAt': Timestamp.fromDate(workout.finishedAt ?? workout.startedAt),
    'programId': ?workout.programId,
    'dayIndex': ?workout.dayIndex,
    'name': workout.name,
    'note': ?workout.note,
    'exerciseIds': workout.exerciseIds,
    'exercises': [
      for (final exercise in workout.exercises)
        WorkoutMaps.exerciseToMap(exercise),
    ],
  };

  /// Null, after logging, for a document without an id, start and finish
  /// time and name.
  static Workout? workoutFromMap(String id, Map<String, dynamic> map) {
    final startedAt = map['startedAt'];
    final finishedAt = map['finishedAt'];
    final name = map['name'];
    final exercises = map['exercises'];
    if (startedAt is! Timestamp ||
        finishedAt is! Timestamp ||
        name is! String) {
      Log.e('workout', 'skipped unreadable workout $id');
      return null;
    }
    final programId = map['programId'];
    final note = map['note'];
    return Workout(
      id: id,
      startedAt: startedAt.toDate(),
      finishedAt: finishedAt.toDate(),
      programId: programId is String ? programId : null,
      dayIndex: WorkoutMaps.whole(map['dayIndex']),
      name: name,
      note: note is String ? note : null,
      exercises: [
        if (exercises is List)
          for (final exercise in exercises)
            ?WorkoutMaps.exerciseFromMap(exercise),
      ],
    );
  }

  static Map<String, Object?> statsToMap(ExerciseStats stats) {
    final last = stats.last;
    return {
      'records': {
        for (final MapEntry(key: kind, value: record) in stats.records.entries)
          kind.code: {
            'value': record.value,
            'date': Timestamp.fromDate(record.date),
            'workoutId': record.workoutId,
          },
      },
      if (last != null)
        'last': {
          'date': Timestamp.fromDate(last.date),
          'workoutId': last.workoutId,
          'sets': [for (final set in last.sets) WorkoutMaps.setToMap(set)],
        },
      'history': [
        for (final point in stats.history)
          {
            'date': Timestamp.fromDate(point.date),
            'workoutId': point.workoutId,
            'bestE1rmKg': ?point.bestE1rmKg,
            'volumeKg': point.volumeKg,
          },
      ],
    };
  }

  /// Null for no document. Records, the last session and history points
  /// that cannot be read are left out.
  static ExerciseStats? statsFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final records = map['records'];
    final last = map['last'];
    final history = map['history'];
    return ExerciseStats(
      records: {
        if (records is Map)
          for (final kind in RecordKind.values)
            kind: ?_record(records[kind.code]),
      },
      last: _last(last),
      history: [
        if (history is List)
          for (final point in history) ?_point(point),
      ]..sort((a, b) => a.date.compareTo(b.date)),
    );
  }

  static StatRecord? _record(Object? raw) {
    if (raw is! Map) return null;
    final value = WorkoutMaps.decimal(raw['value']);
    final date = raw['date'];
    final workoutId = raw['workoutId'];
    if (value == null || date is! Timestamp || workoutId is! String) {
      return null;
    }
    return StatRecord(value: value, date: date.toDate(), workoutId: workoutId);
  }

  static LastSession? _last(Object? raw) {
    if (raw is! Map) return null;
    final date = raw['date'];
    final workoutId = raw['workoutId'];
    if (date is! Timestamp || workoutId is! String) return null;
    return LastSession(
      date: date.toDate(),
      workoutId: workoutId,
      sets: WorkoutMaps.setsFromList(raw['sets']),
    );
  }

  static HistoryPoint? _point(Object? raw) {
    if (raw is! Map) return null;
    final date = raw['date'];
    final workoutId = raw['workoutId'];
    if (date is! Timestamp || workoutId is! String) return null;
    return HistoryPoint(
      date: date.toDate(),
      workoutId: workoutId,
      bestE1rmKg: WorkoutMaps.decimal(raw['bestE1rmKg']),
      volumeKg: WorkoutMaps.decimal(raw['volumeKg']) ?? 0,
    );
  }
}
