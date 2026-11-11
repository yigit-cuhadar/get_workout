import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/cardio_repository.dart';
import '../domain/cardio_session.dart';
import '../domain/cardio_type.dart';

/// Sessions live in `users/{uid}/cardio/{id}`.
class FirestoreCardioRepository implements CardioRepository {
  const FirestoreCardioRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<List<CardioSession>> watchSessions(String uid) =>
      _sessions(uid)
          .watchList((query) => query.orderBy('date', descending: true))
          .transform(
            StreamTransformer.fromHandlers(
              handleError: (error, stack, sink) {
                final failure =
                    mapFirebaseError(error) ?? UnknownFailure('$error', error);
                Log.e('cardio', failure.message, error, stack);
                sink.addError(failure, stack);
              },
            ),
          );

  @override
  Future<Result<void>> saveSession(String uid, CardioSession session) =>
      guard(() async {
        final id = session.id ?? _firestore.collection(_path(uid)).doc().id;
        _confirmLater(_sessions(uid).set(id, session.withId(id)));
      }, mapper: mapFirebaseError);

  @override
  Future<Result<void>> deleteSession(String uid, String id) => guard(
    () async => _confirmLater(_sessions(uid).delete(id)),
    mapper: mapFirebaseError,
  );

  /// Firestore applies a write to its cache at once but completes it only
  /// when the server confirms, which never happens offline, so callers do
  /// not wait for that.
  static void _confirmLater(Future<void> write) => unawaited(
    write.then(
      (_) {},
      onError: (Object error, StackTrace stack) {
        final failure =
            mapFirebaseError(error) ?? UnknownFailure('$error', error);
        Log.e('cardio', 'write rejected: ${failure.message}', error, stack);
      },
    ),
  );

  static String _path(String uid) => 'users/$uid/cardio';

  FirestoreCollection<CardioSession> _sessions(String uid) =>
      FirestoreCollection(
        firestore: _firestore,
        path: _path(uid),
        fromMap: fromMap,
        toMap: toMap,
      );

  static CardioSession fromMap(String id, Map<String, dynamic> map) =>
      CardioSession(
        id: id,
        type: CardioType.fromCode(map['type']),
        date: (map['date'] as Timestamp).toDate(),
        duration: Duration(seconds: (map['durationS'] as num).toInt()),
        distanceKm: (map['distanceKm'] as num?)?.toDouble(),
        calories: (map['calories'] as num?)?.toInt(),
        avgHeartRate: (map['avgHeartRate'] as num?)?.toInt(),
        incline: (map['incline'] as num?)?.toDouble(),
        note: map['note'] as String?,
      );

  /// The id is the document's, not a field. Missing values are left out.
  static Map<String, dynamic> toMap(CardioSession session) => {
    'type': session.type.code,
    'date': Timestamp.fromDate(session.date),
    'durationS': session.duration.inSeconds,
    'distanceKm': ?session.distanceKm,
    'calories': ?session.calories,
    'avgHeartRate': ?session.avgHeartRate,
    'incline': ?session.incline,
    'note': ?session.note,
  };
}
