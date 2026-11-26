import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/exercise.dart';
import '../domain/exercise_animation.dart';
import '../domain/exercise_queries.dart';
import '../domain/exercise_repository.dart';
import '../domain/vocabulary.dart';
import 'exercise_map.dart';
import 'firestore_exercise_source.dart';

/// The catalogue, kept in Firestore's offline cache. A sync reads the cache,
/// then asks the server only for documents with a newer `updatedAt`; a
/// document that left `live` arrives that way too and drops out of the list.
///
/// Documents of every status are read, so the cache can be checked against
/// the server's document count: a cache missing older documents (an
/// interrupted first fetch, eviction) has the right newest `updatedAt` but
/// too few documents, and is then rebuilt with a full fetch.
class FirestoreExerciseRepository implements ExerciseRepository {
  FirestoreExerciseRepository(this._source);

  final FirestoreExerciseSource _source;
  final _changes = StreamController<List<Exercise>>.broadcast();
  List<Exercise>? _current;
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
    var documents = {
      for (final document in cached.valueOrNull ?? <ExerciseDocument>[])
        document.id: document,
    };
    // Show what is there while the server answers. An empty cache is never
    // published: it would read as an empty catalogue.
    if (documents.isNotEmpty) _publish(documents.values);

    final result = await guard(() async {
      final changed = await _source.changedSince(_newestUpdate(documents));
      for (final document in changed) {
        documents[document.id] = document;
      }
      final count = await _source.serverCount();
      if (count != documents.length) {
        Log.d(
          'exercises',
          'Cache has ${documents.length} of $count exercises; full fetch',
        );
        documents = {
          for (final document in await _source.changedSince(null))
            document.id: document,
        };
      }
    }, mapper: mapFirebaseError);

    // After a failure, whatever arrived before it is still worth showing.
    if (result.isOk || documents.isNotEmpty) _publish(documents.values);
    return result;
  }

  /// The cached animation when the cache holds one (or knows there is
  /// none), refreshed from the server for the next read; the server's
  /// otherwise.
  @override
  Future<Result<ExerciseAnimation?>> getAnimation(String exerciseId) =>
      guard(() async {
        final cached = await _cachedAnimation(exerciseId);
        if (cached == null) return _readAnimation(exerciseId, Source.server);
        unawaited(
          _readAnimation(exerciseId, Source.server).then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) => Log.e(
              'exercises',
              'Animation of $exerciseId not refreshed',
              error,
              stack,
            ),
          ),
        );
        return cached.animation;
      }, mapper: mapFirebaseError);

  /// Null when the cache cannot answer: never loaded, or unreadable.
  Future<({ExerciseAnimation? animation})?> _cachedAnimation(
    String exerciseId,
  ) async {
    try {
      return (animation: await _readAnimation(exerciseId, Source.cache));
    } catch (error) {
      Log.d('exercises', 'Animation of $exerciseId not cached: $error');
      return null;
    }
  }

  Future<ExerciseAnimation?> _readAnimation(
    String exerciseId,
    Source source,
  ) async {
    final animation = await _source.animation(exerciseId, source);
    if (animation == null) return null;
    final kits = await _source.animationKits(source);
    if (kits == null) throw const NotFoundFailure('animation kits');
    return ExerciseAnimation(
      recipe: _jsonObject(animation['recipe']),
      kits: _jsonObject(kits['kits']),
    );
  }

  /// Recipes and kits are stored as JSON text: Firestore cannot hold the
  /// arrays inside arrays they are made of.
  static Map<String, Object?> _jsonObject(Object? text) {
    if (text is! String) throw FormatException('Not JSON text', text);
    if (jsonDecode(text) case final Map<String, Object?> map) return map;
    throw FormatException('Not a JSON object', text);
  }

  /// Publishes the live exercises unless they equal the current list.
  void _publish(Iterable<ExerciseDocument> documents) {
    final exercises = [
      for (final document in documents)
        if (document.data['status'] == ExerciseStatus.live.code)
          ?_parse(document),
    ]..sort(compareByPopularity);
    final current = _current;
    if (current != null && _sameList(current, exercises)) return;
    _current = List.unmodifiable(exercises);
    _changes.add(_current!);
  }

  static bool _sameList(List<Exercise> a, List<Exercise> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Exercise? _parse(ExerciseDocument document) {
    try {
      return exerciseFromMap(document.id, document.data);
    } catch (error, stack) {
      Log.e('exercises', 'Skipped exercise ${document.id}', error, stack);
      return null;
    }
  }

  static Timestamp? _newestUpdate(Map<String, ExerciseDocument> documents) {
    Timestamp? newest;
    for (final document in documents.values) {
      if (document.data['updatedAt'] case final Timestamp updatedAt
          when newest == null || updatedAt.compareTo(newest) > 0) {
        newest = updatedAt;
      }
    }
    return newest;
  }
}
