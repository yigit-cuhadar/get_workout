import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:forge_core/forge_core.dart';

import '../domain/rest.dart';
import '../domain/workout.dart';
import '../domain/workout_repository.dart';
import 'workout_maps.dart';

/// Keeps each user's [LocalWorkouts] in a JSON file of its own, named by the
/// user's id, in [directory]. Writes run one at a time and only the latest
/// content of a burst is written; each replaces the file at once (write a
/// temporary file, then rename), so a crash mid-write leaves the previous
/// version, and moving a workout from in progress to finished is one write.
///
/// A file that cannot be read, or is of an unknown version, is renamed to
/// `<name>.unreadable-<time>` and never overwritten; while that rename
/// fails, saves for its user are refused.
class FileLocalWorkoutStore implements LocalWorkoutStore {
  FileLocalWorkoutStore(this._directory, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;

  /// Content waiting to be written per user.
  final _next = <String, String>{};

  /// Users whose unreadable file is still in place.
  final _blocked = <String>{};
  Future<void> _tail = Future.value();

  /// Fields added later are optional, so a newer file of this version
  /// still reads in an older app, which leaves them out.
  static const version = 2;

  @override
  Future<Result<LocalWorkouts>> load(String uid) => guard(() async {
    await _tail;
    final file = await _file(uid);
    if (FileSystemEntity.typeSync(file.path) == FileSystemEntityType.notFound) {
      return const LocalWorkouts();
    }
    try {
      final json = jsonDecode(await file.readAsString());
      final workouts = json is Map && json['uid'] == uid
          ? fromJson(json, now: _clock())
          : null;
      if (workouts == null) throw const FormatException('unknown content');
      _blocked.remove(uid);
      return workouts;
    } on Object catch (error, stack) {
      Log.e('workout', 'kept workouts unreadable', error, stack);
      _blocked.add(uid);
      final aside =
          '${file.path}.unreadable-${_clock().millisecondsSinceEpoch}';
      await file.rename(aside);
      _blocked.remove(uid);
      throw UnknownFailure('kept workouts unreadable; moved to $aside', error);
    }
  });

  @override
  Future<Result<void>> save(String uid, LocalWorkouts workouts) {
    if (_blocked.contains(uid)) {
      return Future.value(
        const Err(UnknownFailure('unreadable kept workouts in the way')),
      );
    }
    _next[uid] = jsonEncode(toJson(uid, workouts));
    final run = _tail.then((_) => _flush(uid));
    _tail = run.catchError((Object _) {});
    return guard(() => run);
  }

  @override
  Future<Result<void>> remove(String uid) {
    _next.remove(uid);
    final run = _tail.then((_) async {
      final file = await _file(uid);
      final directory = file.parent;
      if (!directory.existsSync()) return;
      final name = file.uri.pathSegments.last;
      await for (final entity in directory.list()) {
        final entry = entity.uri.pathSegments.last;
        if (entry == name || entry.startsWith('$name.')) await entity.delete();
      }
    });
    _tail = run.catchError((Object _) {});
    return guard(() => run);
  }

  /// Writes what is waiting for [uid], unless an earlier flush already did.
  Future<void> _flush(String uid) async {
    final content = _next.remove(uid);
    if (content == null) return;
    final file = await _file(uid);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(file.path);
  }

  Future<File> _file(String uid) async {
    final directory = await _directory();
    // Firebase uids are letters and digits; anything else is replaced.
    final name = uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${directory.path}/workouts_$name.json');
  }

  static Map<String, Object?> toJson(String uid, LocalWorkouts workouts) => {
    'version': version,
    'uid': uid,
    'draft': ?switch (workouts.draft) {
      final draft? => _workoutToJson(draft),
      null => null,
    },
    'rest': ?switch (workouts.rest) {
      final rest? when workouts.draft != null => _restToJson(rest),
      _ => null,
    },
    'finished': [for (final w in workouts.finished) _workoutToJson(w)],
    'staleStats': [...workouts.staleStats],
  };

  /// Null for an unknown version or content that is not a known shape.
  /// A rest that cannot be believed at [now] is left out.
  static LocalWorkouts? fromJson(
    Map<Object?, Object?> json, {
    required DateTime now,
  }) {
    if (json['version'] != version) return null;
    final draft = json['draft'];
    final finished = json['finished'];
    final stale = json['staleStats'];
    if (finished is! List || stale is! List) return null;
    final parsedDraft = draft == null ? null : _workoutFromJson(draft);
    final parsedFinished = [for (final w in finished) _workoutFromJson(w)];
    if ((draft != null && parsedDraft == null) ||
        parsedFinished.contains(null)) {
      return null;
    }
    return LocalWorkouts(
      draft: parsedDraft,
      rest: parsedDraft == null
          ? null
          : _restFromJson(json['rest'], parsedDraft, now),
      finished: [for (final w in parsedFinished) w!],
      staleStats: {
        for (final id in stale)
          if (id is String) id,
      },
    );
  }

  static Map<String, Object?> _restToJson(Rest rest) => {
    'endsAt': rest.endsAt.millisecondsSinceEpoch,
    if (rest.after case final after?) ...{
      'exercise': after.exercise,
      'set': after.set,
    },
  };

  /// Null for anything without a believable end (not more than
  /// [maxRestAhead] after [now]); a set that is not in [draft] is dropped.
  /// A rest is never worth losing a workout over, so this never throws.
  static Rest? _restFromJson(Object? json, Workout draft, DateTime now) {
    if (json is! Map) return null;
    final endsAt = json['endsAt'];
    // Beyond what DateTime holds, and long past or far ahead anyway.
    if (endsAt is! int || endsAt.abs() > _maxEpochMs) return null;
    final end = DateTime.fromMillisecondsSinceEpoch(endsAt);
    if (end.isAfter(now.add(maxRestAhead))) return null;
    final exercise = WorkoutMaps.whole(json['exercise']);
    final set = WorkoutMaps.whole(json['set']);
    final known =
        exercise != null &&
        set != null &&
        exercise >= 0 &&
        set >= 0 &&
        exercise < draft.exercises.length &&
        set < draft.exercises[exercise].sets.length;
    return Rest(
      endsAt: end,
      after: known ? (exercise: exercise, set: set) : null,
    );
  }

  static const _maxEpochMs = 8640000000000000;

  static Map<String, Object?> _workoutToJson(Workout workout) => {
    'id': workout.id,
    'startedAt': workout.startedAt.millisecondsSinceEpoch,
    'finishedAt': ?workout.finishedAt?.millisecondsSinceEpoch,
    'programId': ?workout.programId,
    'dayIndex': ?workout.dayIndex,
    'name': workout.name,
    'note': ?workout.note,
    'exercises': [
      for (final exercise in workout.exercises)
        WorkoutMaps.exerciseToMap(exercise, withGoal: true),
    ],
  };

  /// Null for anything without an id, a start time and a name.
  static Workout? _workoutFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final startedAt = json['startedAt'];
    final finishedAt = json['finishedAt'];
    final name = json['name'];
    final exercises = json['exercises'];
    if (id is! String || startedAt is! int || name is! String) return null;
    final programId = json['programId'];
    final note = json['note'];
    return Workout(
      id: id,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
      finishedAt: finishedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(finishedAt)
          : null,
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
