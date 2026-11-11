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

  /// The only language the panel edits.
  static const _language = 'en';

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
  ) async {
    final ref = _exercises.doc(draft.id);
    final written = await guard(
      () => _firestore.runTransaction((transaction) async {
        final stored = (await transaction.get(ref)).data();
        final refused = refuse(stored);
        if (refused == null) transaction.set(ref, _fields(stored, draft));
        return refused;
      }),
      mapper: mapFirebaseError,
    );
    if (written case Ok(value: final refused?)) return Ok(refused);
    if (written case Err(:final failure)) return Err(failure);
    // Committed. Reading the new updatedAt back is a separate step: if it
    // fails, the save still happened and must not be reported as failed.
    final read = await guard(() => _read(ref), mapper: mapFirebaseError);
    return Ok(Saved(read.valueOrNull));
  }

  /// [stored] with the managed fields replaced by [draft]'s. Other languages
  /// of `l10n`, and fields of `l10n.en` the panel does not know, are kept.
  static Map<String, Object?> _fields(
    Map<String, Object?>? stored,
    ExerciseDraft draft,
  ) {
    final content = exerciseContent(draft.toJson());
    final storedL10n = switch (stored?['l10n']) {
      final Map<String, Object?> l10n => l10n,
      _ => const <String, Object?>{},
    };
    final storedText = switch (storedL10n[_language]) {
      final Map<String, Object?> text => text,
      _ => const <String, Object?>{},
    };
    final text =
        (content['l10n']! as Map<String, Object?>)[_language]!
            as Map<String, Object?>;
    return {
      for (final MapEntry(:key, :value) in (stored ?? const {}).entries)
        if (!_managedKeys.contains(key)) key: value,
      ...content,
      'l10n': {
        ...storedL10n,
        _language: {
          for (final MapEntry(:key, :value) in storedText.entries)
            if (!allowedTextKeys.contains(key)) key: value,
          ...text,
        },
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
