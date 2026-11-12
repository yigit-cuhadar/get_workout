import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../../../features/exercises/domain/content_rules.dart';
import '../../../features/programs/domain/catalogue_rules.dart';
import '../domain/admin_program_repository.dart';
import '../domain/program_draft.dart';

/// Edits `programs/{id}` and `programs/{id}/detail/main` directly, in the
/// shape the import writes (`tool/src/content_import.dart`, `programDocs`).
/// Each save is one transaction, so the card and the detail are committed
/// together or not at all: it reads both, refuses when either changed since
/// the editor loaded them, and writes the managed fields over what is
/// stored, so `contentHash` (which tells the import the program was edited
/// here) and unknown fields stay. The days are replaced as a whole.
class FirestoreAdminProgramRepository implements AdminProgramRepository {
  const FirestoreAdminProgramRepository(this._firestore);

  final FirebaseFirestore _firestore;

  /// Fields of the card the editor owns; every other stored field is kept.
  static final _managedCardKeys = programKeys.difference({'id', 'days'});

  CollectionReference<Map<String, dynamic>> get _programs =>
      _firestore.collection('programs');

  DocumentReference<Map<String, dynamic>> _detail(String id) =>
      _programs.doc(id).collection('detail').doc('main');

  @override
  Stream<List<ProgramRecord>> watchCards() => _programs
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs) _record(doc.id, doc.data(), null),
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
  Future<Result<ProgramRecord>> load(String id) =>
      guard(() => _read(id), mapper: mapFirebaseError);

  @override
  Future<Result<ProgramSaveOutcome>> create(Map<String, Object?> content) =>
      _save(content, (card, _) => card == null ? null : const ProgramIdTaken());

  @override
  Future<Result<ProgramSaveOutcome>> update(
    Map<String, Object?> content, {
    required ProgramVersion loaded,
  }) => _save(
    content,
    (card, detail) => card != null && _version(card, detail) == loaded
        ? null
        : const ProgramChangedSinceLoaded(),
  );

  /// Writes [content] unless [refuse], given the stored card and detail
  /// (null when absent), returns why not.
  Future<Result<ProgramSaveOutcome>> _save(
    Map<String, Object?> content,
    ProgramSaveOutcome? Function(
      Map<String, Object?>? card,
      Map<String, Object?>? detail,
    )
    refuse,
  ) async {
    final id = content['id']! as String;
    final cardRef = _programs.doc(id);
    final detailRef = _detail(id);
    final written = await guard(
      () => _firestore.runTransaction((transaction) async {
        final card = (await transaction.get(cardRef)).data();
        final detail = (await transaction.get(detailRef)).data();
        final refused = refuse(card, detail);
        if (refused == null) {
          transaction
            ..set(cardRef, _cardFields(card, content))
            ..set(detailRef, _detailFields(detail, content));
        }
        return refused;
      }),
      mapper: mapFirebaseError,
    );
    if (written case Ok(value: final refused?)) return Ok(refused);
    if (written case Err(:final failure)) return Err(failure);
    // Committed. Reading the new versions back is a separate step: if it
    // fails, the save still happened and must not be reported as failed.
    final read = await guard(() => _read(id), mapper: mapFirebaseError);
    return Ok(ProgramSaved(read.valueOrNull));
  }

  /// [stored] with the managed card fields replaced by [content]'s. The
  /// text of languages the panel does not edit, and fields of a text it
  /// does not know, are kept.
  static Map<String, Object?> _cardFields(
    Map<String, Object?>? stored,
    Map<String, Object?> content,
  ) {
    final storedL10n = switch (stored?['l10n']) {
      final Map<String, Object?> l10n => l10n,
      _ => const <String, Object?>{},
    };
    final l10n = content['l10n']! as Map<String, Object?>;
    return {
      for (final MapEntry(:key, :value) in (stored ?? const {}).entries)
        if (!_managedCardKeys.contains(key)) key: value,
      for (final MapEntry(:key, :value) in content.entries)
        if (_managedCardKeys.contains(key) && key != 'l10n') key: value,
      'l10n': {
        for (final MapEntry(:key, :value) in storedL10n.entries)
          if (!languages.contains(key)) key: value,
        for (final MapEntry(key: language, :value) in l10n.entries)
          language: {
            if (storedL10n[language] case final Map<String, Object?> text)
              for (final MapEntry(:key, :value) in text.entries)
                if (!programTextKeys.contains(key)) key: value,
            ...value! as Map<String, Object?>,
          },
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static Map<String, Object?> _detailFields(
    Map<String, Object?>? stored,
    Map<String, Object?> content,
  ) => {
    ...?stored,
    'days': content['days'],
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Future<ProgramRecord> _read(String id) async {
    const server = GetOptions(source: Source.server);
    final card = (await _programs.doc(id).get(server)).data();
    if (card == null) throw NotFoundFailure('programs/$id');
    final detail = (await _detail(id).get(server)).data();
    return _record(id, card, detail);
  }

  /// [card] and, when read, [detail] in the content-file shape.
  static ProgramRecord _record(
    String id,
    Map<String, Object?> card,
    Map<String, Object?>? detail,
  ) {
    final days = detail?['days'];
    final json = _wholeNumbers({
      'id': id,
      ...Map.of(card)
        ..remove('updatedAt')
        ..remove('contentHash'),
      'days': ?days,
    });
    return ProgramRecord(
      json: json! as Map<String, Object?>,
      version: _version(card, detail),
    );
  }

  /// A program holds whole numbers only. A web client (the panel) stores
  /// them as integers, the import too, but a double that is whole (written
  /// elsewhere) reads as the same number.
  static Object? _wholeNumbers(Object? value) => switch (value) {
    final double number
        when number.isFinite && number == number.roundToDouble() =>
      number.round(),
    final Map<Object?, Object?> map => <String, Object?>{
      for (final MapEntry(:key, :value) in map.entries)
        '$key': _wholeNumbers(value),
    },
    final List<Object?> list => [for (final item in list) _wholeNumbers(item)],
    _ => value,
  };

  static ProgramVersion _version(
    Map<String, Object?> card,
    Map<String, Object?>? detail,
  ) => (card: _updatedAt(card), detail: _updatedAt(detail));

  static DateTime? _updatedAt(Map<String, Object?>? data) =>
      switch (data?['updatedAt']) {
        final Timestamp updatedAt => updatedAt.toDate(),
        _ => null,
      };
}
