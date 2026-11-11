import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/custom_exercise.dart';
import '../domain/custom_exercise_repository.dart';
import '../domain/exercise.dart';
import '../domain/vocabulary.dart';

/// Custom exercises live in `users/{uid}/customExercises/{id}`, the id being
/// [Exercise.customIdPrefix] plus a Firestore auto id. Favourites are
/// `favoriteExerciseIds` of `users/{uid}`, shared with other features, so
/// that write merges. `FirestoreCollection` is not used: its converter fails
/// the whole stream on one bad document, and it offers only whole-document
/// writes.
class FirestoreCustomExerciseRepository implements CustomExerciseRepository {
  FirestoreCustomExerciseRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final _rejected = StreamController<Failure>.broadcast();

  @override
  Stream<Failure> get rejectedWrites => _rejected.stream;

  @override
  Stream<List<CustomExercise>> watchCustomExercises(String uid) =>
      _exercises(uid)
          .snapshots()
          .map(
            (snap) => [
              for (final doc in snap.docs) ?fromMap(doc.id, doc.data()),
            ],
          )
          .transform(
            StreamTransformer.fromHandlers(
              handleError: (error, stack, sink) {
                final failure =
                    mapFirebaseError(error) ?? UnknownFailure('$error', error);
                Log.e('customExercises', failure.message, error, stack);
                sink.addError(failure, stack);
              },
            ),
          );

  @override
  Future<Result<int>> countCustomExercises(String uid) => guard(
    () async => (await _exercises(uid).snapshots().first).size,
    mapper: mapFirebaseError,
  );

  @override
  Future<Result<void>> createCustomExercise(
    String uid,
    CustomExercise exercise,
  ) => guard(() async {
    final id = '${Exercise.customIdPrefix}${_exercises(uid).doc().id}';
    _confirmLater(_exercises(uid).doc(id).set(toMap(exercise)));
  }, mapper: mapFirebaseError);

  /// An update, not a set, so fields a newer app version stored are kept.
  @override
  Future<Result<void>> updateCustomExercise(
    String uid,
    CustomExercise exercise,
  ) => guard(() async {
    _confirmLater(
      _exercises(uid).doc(exercise.id).update({
        ...toMap(exercise),
        if (exercise.note == null) 'note': FieldValue.delete(),
      }),
    );
  }, mapper: mapFirebaseError);

  @override
  Future<Result<void>> deleteCustomExercise(String uid, String id) =>
      guard(() async {
        _confirmLater(
          (_firestore.batch()
                ..delete(_exercises(uid).doc(id))
                ..set(_firestore.collection('users').doc(uid), {
                  'favoriteExerciseIds': FieldValue.arrayRemove([id]),
                }, SetOptions(merge: true)))
              .commit(),
        );
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
        Log.e(
          'customExercises',
          'write rejected: ${failure.message}',
          error,
          stack,
        );
        _rejected.add(failure);
      },
    ),
  );

  CollectionReference<Map<String, dynamic>> _exercises(String uid) =>
      _firestore.collection('users/$uid/customExercises');

  /// Null, after logging, for a document without a name, a known logging
  /// type and a known main muscle. Unknown muscle and equipment codes (a
  /// newer app version's) are skipped.
  static CustomExercise? fromMap(String id, Map<String, dynamic> map) {
    final name = map['name'];
    final loggingType = LoggingType.values.byCode(map['loggingType']);
    final main = _codes(map['mainMuscles'], Muscle.values);
    if (name is! String ||
        name.isEmpty ||
        loggingType == null ||
        main.isEmpty) {
      Log.e('customExercises', 'skipped unreadable custom exercise $id');
      return null;
    }
    final note = map['note'];
    return CustomExercise(
      id: id,
      name: name,
      loggingType: loggingType,
      mainMuscles: main,
      secondaryMuscles: _codes(map['secondaryMuscles'], Muscle.values),
      equipment: _codes(map['equipment'], Equipment.values),
      note: note is String && note.isNotEmpty ? note : null,
    );
  }

  /// The stored fields; the id is the document's, a missing note left out.
  static Map<String, Object?> toMap(CustomExercise exercise) => {
    'name': exercise.name,
    'loggingType': exercise.loggingType.code,
    'mainMuscles': [for (final muscle in exercise.mainMuscles) muscle.code],
    'secondaryMuscles': [
      for (final muscle in exercise.secondaryMuscles) muscle.code,
    ],
    'equipment': [for (final item in exercise.equipment) item.code],
    'note': ?exercise.note,
  };

  static List<T> _codes<T extends Coded>(Object? raw, List<T> values) => [
    if (raw is List)
      for (final code in raw) ?values.byCode(code),
  ];
}
