import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../../../features/exercises/data/exercise_content.dart';
import '../../../features/exercises/domain/content_rules.dart';
import '../domain/admin_exercise_repository.dart';
import '../domain/exercise_draft.dart';

/// Edits `exercises/{id}` directly. Each save is one transaction: it reads
/// the document, refuses when it changed since the editor loaded it, and
/// writes the managed fields over what is stored, so `contentHash` (which
/// tells the importer the document was edited here) and unknown fields stay.
/// `FirestoreCollection` has no transactions, hence the direct access.
class FirestoreAdminExerciseRepository implements AdminExerciseRepository {
  const FirestoreAdminExerciseRepository(this._firestore);

  final FirebaseFirestore _firestore;

  /// Fields the editor owns; every other stored field is kept as it is.
  static final _managedKeys = allowedKeys.difference({'id'});

  CollectionReference<Map<String, dynamic>> get _exercises =>
      _firestore.collection('exercises');

  @override
  Stream<List<ExerciseRecord>> watchAll() => _exercises
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs) _record(doc.id, doc.data()),
        ],
      )
      .transform(
        StreamTransformer.fromHandlers(
          handleError: (error, stack, sink) {
            final failure =
                mapFirebaseError(error) ?? UnknownFailure('$error', error);
            Log.e('admin', failure.message, error, stack);
            sink.addError(failure, stack);
          },
        ),
      );

  @override
  Future<Result<ExerciseRecord>> load(String id) =>
      guard(() => _read(_exercises.doc(id)), mapper: mapFirebaseError);

  @override
  Future<Result<SaveOutcome>> create(ExerciseDraft draft) =>
      _save(draft, (stored) => stored == null ? null : const IdTaken());

  @override
  Future<Result<SaveOutcome>> update(
    ExerciseDraft draft, {
    required DateTime? loadedUpdatedAt,
  }) => _save(
    draft,
    (stored) => stored != null && _updatedAt(stored) == loadedUpdatedAt
        ? null
        : const ChangedSinceLoaded(),
  );

  /// Writes [draft] unless [refuse], given the stored fields (null when
  /// there is no document), returns why not.
  Future<Result<SaveOutcome>> _save(
    ExerciseDraft draft,
    SaveOutcome? Function(Map<String, Object?>? stored) refuse,
  ) => guard(() async {
    final ref = _exercises.doc(draft.id);
    final refused = await _firestore.runTransaction((transaction) async {
      final stored = (await transaction.get(ref)).data();
      final refused = refuse(stored);
      if (refused == null) transaction.set(ref, _fields(stored, draft));
      return refused;
    });
    return refused ?? Saved(await _read(ref));
  }, mapper: mapFirebaseError);

  /// [stored] with the managed fields replaced by [draft]'s. Other languages
  /// of `l10n` are kept; the panel edits English only.
  static Map<String, Object?> _fields(
    Map<String, Object?>? stored,
    ExerciseDraft draft,
  ) {
    final content = exerciseContent(draft.toJson());
    final storedL10n = stored?['l10n'];
    return {
      for (final MapEntry(:key, :value) in (stored ?? const {}).entries)
        if (!_managedKeys.contains(key)) key: value,
      ...content,
      'l10n': {
        if (storedL10n is Map<String, Object?>) ...storedL10n,
        ...content['l10n']! as Map<String, Object?>,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static Future<ExerciseRecord> _read(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    final snapshot = await ref.get(const GetOptions(source: Source.server));
    final data = snapshot.data();
    if (data == null) throw NotFoundFailure(ref.path);
    return _record(snapshot.id, data);
  }

  static ExerciseRecord _record(String id, Map<String, Object?> data) =>
      ExerciseRecord(
        json: exerciseJson(
          id,
          Map.of(data)
            ..remove('updatedAt')
            ..remove('contentHash'),
        ),
        updatedAt: _updatedAt(data),
      );

  static DateTime? _updatedAt(Map<String, Object?> data) =>
      switch (data['updatedAt']) {
        final Timestamp updatedAt => updatedAt.toDate(),
        _ => null,
      };
}
