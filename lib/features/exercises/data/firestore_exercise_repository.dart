import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/exercise.dart';
import '../domain/exercise_repository.dart';
import '../domain/vocabulary.dart';
import 'exercise_map.dart';
import 'firestore_exercise_source.dart';

/// The catalogue, kept in Firestore's offline cache. A sync reads the cache,
/// then asks the server only for documents with a newer `updatedAt`; a
/// document that left `live` arrives that way too and drops out of the list.
class FirestoreExerciseRepository implements ExerciseRepository {
  FirestoreExerciseRepository(this._source);

  final FirestoreExerciseSource _source;
  final _changes = StreamController<List<Exercise>>.broadcast();
  List<Exercise>? _current;

  /// Newest `updatedAt` among the documents [_current] was built from.
  Timestamp? _currentNewest;
  Future<Result<void>>? _syncing;

  @override
  Stream<List<Exercise>> watchExercises() {
    StreamSubscription<List<Exercise>>? changes;
    late final StreamController<List<Exercise>> controller;
    controller = StreamController(
      onListen: () {
        if (_current case final current?) controller.add(current);
        changes = _changes.stream.listen(controller.add);
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  /// Calls made while one runs share its result.
  @override
  Future<Result<void>> sync() =>
      _syncing ??= _sync().whenComplete(() => _syncing = null);

  Future<Result<void>> _sync() async {
    final cached = await guard(_source.cached, mapper: mapFirebaseError);
    final documents = {
      for (final document in cached.valueOrNull ?? <ExerciseDocument>[])
        document.id: document,
    };
    // Show what is there while the server answers; an empty cache is not
    // shown so a first sync goes straight from nothing to the full list.
    if (_current == null && documents.isNotEmpty) _publish(documents.values);

    final changed = await guard(
      () => _source.changedSince(_newestUpdate(documents.values)),
      mapper: mapFirebaseError,
    );
    for (final document in changed.valueOrNull ?? <ExerciseDocument>[]) {
      documents[document.id] = document;
    }
    // Also catches documents that reached the cache some other way.
    if (_current == null || _newestUpdate(documents.values) != _currentNewest) {
      _publish(documents.values);
    }
    return changed.map((_) {});
  }

  void _publish(Iterable<ExerciseDocument> documents) {
    final exercises = [
      for (final document in documents)
        if (document.data['status'] == ExerciseStatus.live.code)
          ?_parse(document),
    ]..sort((a, b) => a.popularity.compareTo(b.popularity));
    _current = List.unmodifiable(exercises);
    _currentNewest = _newestUpdate(documents);
    _changes.add(_current!);
  }

  static Exercise? _parse(ExerciseDocument document) {
    try {
      return exerciseFromMap(document.id, document.data);
    } catch (error, stack) {
      Log.e('exercises', 'Skipped exercise ${document.id}', error, stack);
      return null;
    }
  }

  static Timestamp? _newestUpdate(Iterable<ExerciseDocument> documents) {
    Timestamp? newest;
    for (final document in documents) {
      if (document.data['updatedAt'] case final Timestamp updatedAt
          when newest == null || updatedAt.compareTo(newest) > 0) {
        newest = updatedAt;
      }
    }
    return newest;
  }
}
