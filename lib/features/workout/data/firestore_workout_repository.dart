import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/exercise_stats.dart';
import '../domain/workout.dart';
import '../domain/workout_repository.dart';
import 'workout_maps.dart';

/// Workouts live in `users/{uid}/workouts/{id}`, stats in
/// `users/{uid}/exerciseStats/{exerciseId}`. `FirestoreCollection` is not
/// used: a workout and its stats go in one batch, and a bad document must
/// not fail a whole stream.
class FirestoreWorkoutRepository implements WorkoutRepository {
  FirestoreWorkoutRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final _rejected = StreamController<Failure>.broadcast();

  @override
  Stream<Failure> get rejectedWrites => _rejected.stream;

  @override
  String newWorkoutId(String uid) => _workouts(uid).doc().id;

  @override
  Stream<ExerciseStats?> watchStats(String uid, String exerciseId) =>
      _stats(uid)
          .doc(exerciseId)
          .snapshots()
          .map((snap) => statsFromMap(snap.data()))
          .transform(
            StreamTransformer.fromHandlers(
              handleError: (error, stack, sink) {
                final failure =
                    mapFirebaseError(error) ?? UnknownFailure('$error', error);
                Log.e('workout', failure.message, error, stack);
                sink.addError(failure, stack);
              },
            ),
          );

  @override
  Future<Result<Map<String, ExerciseStats?>>> getStats(
    String uid,
    List<String> exerciseIds,
  ) => guard(() async {
    final stats = <String, ExerciseStats?>{};
    for (final id in exerciseIds) {
      final doc = await _read(_stats(uid).doc(id));
      if (doc != null) stats[id] = statsFromMap(doc.data());
    }
    return stats;
  }, mapper: mapFirebaseError);

  /// From the cache, which listeners keep current, so this is instant and
  /// works offline; from the server when the document was never loaded.
  /// Null when neither can be reached.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> _read(
    DocumentReference<Map<String, dynamic>> doc,
  ) async {
    try {
      return await doc.get(const GetOptions(source: Source.cache));
    } on FirebaseException {
      try {
        return await doc.get();
      } on FirebaseException catch (error, stack) {
        Log.e('workout', 'stats ${doc.id} unreadable', error, stack);
        return null;
      }
    }
  }

  @override
  Future<Result<void>> saveWorkout(
    String uid,
    Workout workout,
    Map<String, ExerciseStats> stats,
  ) => guard(() async {
    final batch = _firestore.batch()
      ..set(_workouts(uid).doc(workout.id), workoutToMap(workout));
    for (final MapEntry(key: id, value: value) in stats.entries) {
      batch.set(_stats(uid).doc(id), statsToMap(value));
    }
    _confirmLater(batch.commit());
  }, mapper: mapFirebaseError);

  /// Firestore applies a write to its cache at once but completes it only
  /// when the server confirms, which never happens offline, so callers do
  /// not wait for that.
  void _confirmLater(Future<void> write) => unawaited(
    write.then(
      (_) {},
      onError: (Object error, StackTrace stack) {
        final failure =
            mapFirebaseError(error) ?? UnknownFailure('$error', error);
        Log.e('workout', 'write rejected: ${failure.message}', error, stack);
        _rejected.add(failure);
      },
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
