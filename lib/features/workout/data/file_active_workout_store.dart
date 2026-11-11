import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:forge_core/forge_core.dart';

import '../domain/workout.dart';
import '../domain/workout_repository.dart';
import 'workout_maps.dart';

/// Keeps each user's workout in progress in a JSON file of its own, named
/// by the user's id, in [directory]. Writes run one at a time and only the
/// latest content of a burst is written; each replaces the file at once
/// (write a temporary file, then rename), so a crash mid-write leaves the
/// previous version.
class FileActiveWorkoutStore implements ActiveWorkoutStore {
  FileActiveWorkoutStore(this._directory);

  final Future<Directory> Function() _directory;

  /// Content waiting to be written per user; null deletes the file.
  final _next = <String, String?>{};
  Future<void> _tail = Future.value();

  @override
  Future<Result<Workout?>> load(String uid) => guard(() async {
    await _tail;
    final file = await _file(uid);
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map && json['uid'] == uid ? fromJson(json) : null;
    } on FormatException catch (error, stack) {
      Log.e('workout', 'unreadable workout in progress', error, stack);
      return null;
    }
  });

  @override
  Future<Result<void>> save(String uid, Workout workout) =>
      _enqueue(uid, jsonEncode(toJson(uid, workout)));

  @override
  Future<Result<void>> clear(String uid) => _enqueue(uid, null);

  Future<Result<void>> _enqueue(String uid, String? content) {
    _next[uid] = content;
    final run = _tail.then((_) => _flush(uid));
    _tail = run.catchError((Object _) {});
    return guard(() => run);
  }

  /// Writes what is waiting for [uid], unless an earlier flush already did.
  Future<void> _flush(String uid) async {
    if (!_next.containsKey(uid)) return;
    final content = _next.remove(uid);
    final file = await _file(uid);
    if (content == null) {
      if (file.existsSync()) await file.delete();
      return;
    }
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(file.path);
  }

  Future<File> _file(String uid) async {
    final directory = await _directory();
    // Firebase uids are letters and digits; anything else is replaced.
    final name = uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${directory.path}/active_workout_$name.json');
  }

  static Map<String, Object?> toJson(String uid, Workout workout) => {
    'uid': uid,
    'id': workout.id,
    'startedAt': workout.startedAt.millisecondsSinceEpoch,
    'programId': ?workout.programId,
    'dayIndex': ?workout.dayIndex,
    'name': workout.name,
    'note': ?workout.note,
    'exercises': [
      for (final exercise in workout.exercises)
        WorkoutMaps.exerciseToMap(exercise, withGoal: true),
    ],
  };

  /// Null for content without an id, a start time and a name.
  static Workout? fromJson(Map<Object?, Object?> json) {
    final id = json['id'];
    final startedAt = json['startedAt'];
    final name = json['name'];
    final exercises = json['exercises'];
    if (id is! String || startedAt is! int || name is! String) return null;
    final programId = json['programId'];
    final note = json['note'];
    return Workout(
      id: id,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
      programId: programId is String ? programId : null,
      dayIndex: WorkoutMaps.whole(json['dayIndex']),
      name: name,
      note: note is String ? note : null,
      exercises: [
        if (exercises is List)
          for (final exercise in exercises)
            ?WorkoutMaps.exerciseFromMap(exercise),
      ],
    );
  }
}
