import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/body_entry.dart';
import '../domain/body_repository.dart';

/// Entries live in `users/{uid}/bodyEntries/{id}`. `FirestoreCollection` is
/// not used: its converter fails the whole stream on one bad document, and
/// it has no update that removes single map keys.
class FirestoreBodyRepository implements BodyRepository {
  FirestoreBodyRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final _rejected = StreamController<Failure>.broadcast();

  /// Years of weekly entries.
  static const maxEntries = 1000;

  @override
  Stream<Failure> get rejectedWrites => _rejected.stream;

  @override
  Stream<List<BodyEntry>> watchEntries(String uid) => _entries(uid)
      .orderBy('date', descending: true)
      .limit(maxEntries)
      .snapshots()
      .map(
        (snap) => [for (final doc in snap.docs) ?fromMap(doc.id, doc.data())],
      )
      .transform(
        StreamTransformer.fromHandlers(
          handleError: (error, stack, sink) {
            final failure =
                mapFirebaseError(error) ?? UnknownFailure('$error', error);
            Log.e('body', failure.message, error, stack);
            sink.addError(failure, stack);
          },
        ),
      );

  @override
  String newEntryId(String uid) => _entries(uid).doc().id;

  @override
  Future<Result<void>> addEntry(String uid, BodyEntry entry) => guard(
    () async => _confirmLater(_entries(uid).doc(entry.id).set(toMap(entry))),
    mapper: mapFirebaseError,
  );

  @override
  Future<Result<void>> updateEntry(String uid, BodyEntry entry) => guard(
    () async =>
        _confirmLater(_entries(uid).doc(entry.id).update(_update(entry))),
    mapper: mapFirebaseError,
  );

  @override
  Future<Result<void>> deleteEntry(String uid, String id) => guard(
    () async => _confirmLater(_entries(uid).doc(id).delete()),
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
        Log.e('body', 'write rejected: ${failure.message}', error, stack);
        _rejected.add(failure);
      },
    ),
  );

  CollectionReference<Map<String, dynamic>> _entries(String uid) =>
      _firestore.collection('users/$uid/bodyEntries');

  /// Every known field, by its path, so unknown map keys survive.
  static Map<String, Object?> _update(BodyEntry entry) => {
    'date': Timestamp.fromDate(entry.date),
    'weightKg': entry.weightKg ?? FieldValue.delete(),
    for (final measurement in BodyMeasurement.values)
      'measurements.${measurement.code}':
          entry.measurements[measurement] ?? FieldValue.delete(),
    for (final pose in PhotoPose.values)
      'photos.${pose.code}': entry.photos[pose] ?? FieldValue.delete(),
  };

  /// Null, after logging, for a document without a readable date. Values of
  /// the wrong type, and unknown keys, are left out.
  static BodyEntry? fromMap(String id, Map<String, dynamic> map) {
    final date = map['date'];
    if (date is! Timestamp) {
      Log.e('body', 'skipped unreadable entry $id');
      return null;
    }
    final weight = map['weightKg'];
    final measurements = map['measurements'];
    final photos = map['photos'];
    return BodyEntry(
      id: id,
      date: date.toDate(),
      weightKg: weight is num && weight.isFinite ? weight.toDouble() : null,
      measurements: {
        if (measurements is Map)
          for (final MapEntry(:key, :value) in measurements.entries)
            if ((BodyMeasurement.fromCode(key), value)
                case (final measurement?, final num cm) when cm.isFinite)
              measurement: cm.toDouble(),
      },
      photos: {
        if (photos is Map)
          for (final MapEntry(:key, :value) in photos.entries)
            if ((PhotoPose.fromCode(key), value) case (
              final pose?,
              final String path,
            ))
              pose: path,
      },
    );
  }

  /// A new document: the id is the document's; a quick weight log has
  /// neither map.
  static Map<String, Object?> toMap(BodyEntry entry) => {
    'date': Timestamp.fromDate(entry.date),
    'weightKg': ?entry.weightKg,
    if (entry.measurements.isNotEmpty)
      'measurements': {
        for (final MapEntry(:key, :value) in entry.measurements.entries)
          key.code: value,
      },
    if (entry.photos.isNotEmpty)
      'photos': {
        for (final MapEntry(:key, :value) in entry.photos.entries)
          key.code: value,
      },
  };
}
