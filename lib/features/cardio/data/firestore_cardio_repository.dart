import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/cardio_repository.dart';
import '../domain/cardio_session.dart';
import '../domain/cardio_type.dart';

/// Sessions live in `users/{uid}/cardio/{id}`. `FirestoreCollection` is not
/// used: its converter fails the whole stream on one bad document, and it
/// has no partial update that removes fields.
class FirestoreCardioRepository implements CardioRepository {
  FirestoreCardioRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final _rejected = StreamController<Failure>.broadcast();

  /// Older history arrives with the Progress features.
  static const maxSessions = 500;

  /// Far above any real value, far below where rounding fails.
  static const _maxWhole = 1e9;

  static const _fieldNames = {
    CardioField.distanceKm: 'distanceKm',
    CardioField.calories: 'calories',
    CardioField.avgHeartRate: 'avgHeartRate',
    CardioField.incline: 'incline',
    CardioField.note: 'note',
  };

  @override
  Stream<Failure> get rejectedWrites => _rejected.stream;

  @override
  Stream<List<CardioSession>> watchSessions(String uid) => _sessions(uid)
      .orderBy('date', descending: true)
      .limit(maxSessions)
      .snapshots()
      .map(
        (snap) => [for (final doc in snap.docs) ?fromMap(doc.id, doc.data())],
      )
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
  Future<Result<void>> saveSession(
    String uid,
    CardioSession session, {
    required Set<CardioField> fields,
  }) => guard(() async {
    final id = session.id;
    if (id == null) {
      _confirmLater(_sessions(uid).doc().set(toMap(session)));
    } else {
      _confirmLater(_sessions(uid).doc(id).update(_update(session, fields)));
    }
  }, mapper: mapFirebaseError);

  @override
  Future<Result<void>> deleteSession(String uid, String id) => guard(
    () async => _confirmLater(_sessions(uid).doc(id).delete()),
    mapper: mapFirebaseError,
  );

  /// Firestore applies a write to its cache at once but completes it only
  /// when the server confirms, which never happens offline, so callers do
  /// not wait for that.
  void _confirmLater(Future<void> write) => unawaited(
    write.then(
      (_) {},
      onError: (Object error, StackTrace stack) {
        final failure =
            mapFirebaseError(error) ?? UnknownFailure('$error', error);
        Log.e('cardio', 'write rejected: ${failure.message}', error, stack);
        _rejected.add(failure);
      },
    ),
  );

  CollectionReference<Map<String, dynamic>> _sessions(String uid) =>
      _firestore.collection('users/$uid/cardio');

  static Map<String, Object?> _update(
    CardioSession session,
    Set<CardioField> fields,
  ) {
    final values = _optional(session);
    return {
      'type': session.typeCode,
      'date': Timestamp.fromDate(session.date),
      'durationS': session.duration.inSeconds,
      for (final field in fields)
        _fieldNames[field]!: values[field] ?? FieldValue.delete(),
    };
  }

  static Map<CardioField, Object?> _optional(CardioSession session) => {
    CardioField.distanceKm: session.distanceKm,
    CardioField.calories: session.calories,
    CardioField.avgHeartRate: session.avgHeartRate,
    CardioField.incline: session.incline,
    CardioField.note: session.note,
  };

  /// Null, after logging, for a document without a readable type, date and
  /// duration of up to a day (what the rules allow). Optional values of the
  /// wrong type, or too large to be real, read as missing.
  static CardioSession? fromMap(String id, Map<String, dynamic> map) {
    final type = map['type'];
    final date = map['date'];
    final seconds = map['durationS'];
    if (type is! String ||
        date is! Timestamp ||
        seconds is! num ||
        !(seconds > 0 && seconds <= Duration.secondsPerDay)) {
      Log.e('cardio', 'skipped unreadable session $id');
      return null;
    }
    double? decimal(Object? value) =>
        value is num && value.isFinite ? value.toDouble() : null;
    int? whole(Object? value) =>
        value is num && value.abs() <= _maxWhole ? value.round() : null;
    final note = map['note'];
    return CardioSession(
      id: id,
      type: CardioType.fromCode(type),
      typeCode: type,
      date: date.toDate(),
      duration: Duration(seconds: seconds.round()),
      distanceKm: decimal(map['distanceKm']),
      calories: whole(map['calories']),
      avgHeartRate: whole(map['avgHeartRate']),
      incline: decimal(map['incline']),
      note: note is String ? note : null,
    );
  }

  /// A new document: the id is the document's, missing values are left out.
  static Map<String, Object?> toMap(CardioSession session) => {
    'type': session.typeCode,
    'date': Timestamp.fromDate(session.date),
    'durationS': session.duration.inSeconds,
    for (final MapEntry(:key, :value) in _optional(session).entries)
      _fieldNames[key]!: ?value,
  };
}
