// Validates the exercise animations in content/animations: the recipes
// (<exercise id>.json) and the gear kits (_kits.json), in the format of
// tool/animation/recipe.py, against the catalogue. Geometry is checked by
// tool/animation/validate.py.
import 'dart:convert';
import 'dart:io';

import 'package:get_workout/features/exercises/domain/content_rules.dart';

const kitsFile = '_kits.json';
const recipeStatuses = {'draft', 'review', 'approved', 'fix'};
const kitStatuses = {'draft', 'approved'};

/// A recipe file, `content/animations/<id>.json`.
class RecipeEntry {
  RecipeEntry(this.id, this.data);

  /// The exercise it animates.
  final String id;
  final Map<String, Object?> data;

  bool get isApproved => data['status'] == 'approved';
}

/// What [validateAnimations] read.
class AnimationContent {
  AnimationContent(this.kits, this.recipes);

  /// Kit name to kit.
  final Map<String, Object?> kits;
  final List<RecipeEntry> recipes;
}

/// Reads the kits and the recipes in [dir] (which must exist), adding a
/// problem to [errors] for each rule broken. [library] is the catalogue by
/// id.
AnimationContent validateAnimations(
  Directory dir,
  Map<String, ExerciseEntry> library,
  List<String> errors,
) {
  final kits = _kits(File('${dir.path}/$kitsFile'), errors);
  final recipes = <RecipeEntry>[];
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .where((f) => !f.path.endsWith('/$kitsFile'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final id = name.substring(0, name.length - '.json'.length);
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      errors.add('$name: invalid JSON: ${e.message}');
      continue;
    }
    if (decoded is! Map<String, Object?>) {
      errors.add('$name: top level must be a JSON object');
      continue;
    }
    final exercise = library[id];
    if (exercise == null) {
      errors.add('$name: no catalogue exercise $id');
      continue;
    }
    final recipe = RecipeEntry(id, decoded);
    errors.addAll([
      for (final problem in _recipeProblems(recipe, exercise, kits))
        '$name: $problem',
    ]);
    recipes.add(recipe);
  }
  return AnimationContent(kits, recipes);
}

Map<String, Object?> _kits(File file, List<String> errors) {
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FileSystemException {
    errors.add('$kitsFile: missing');
    return const {};
  } on FormatException catch (e) {
    errors.add('$kitsFile: invalid JSON: ${e.message}');
    return const {};
  }
  if (decoded is! Map<String, Object?>) {
    errors.add('$kitsFile: top level must be a JSON object');
    return const {};
  }
  for (final MapEntry(key: name, value: kit) in decoded.entries) {
    if (kit is! Map<String, Object?>) {
      errors.add('$kitsFile: kit $name is not an object');
    } else if (!kitStatuses.contains(kit['status'])) {
      errors.add(
        '$kitsFile: kit $name has status ${kit['status']}, not one of '
        '${kitStatuses.join(', ')}',
      );
    }
  }
  return decoded;
}

List<String> _recipeProblems(
  RecipeEntry recipe,
  ExerciseEntry exercise,
  Map<String, Object?> kits,
) {
  final data = recipe.data;
  final problems = <String>[];
  if (!recipeStatuses.contains(data['status'])) {
    problems.add(
      'status ${data['status']} is not one of ${recipeStatuses.join(', ')}',
    );
  }
  final poses = data['poses'];
  final poseNames = poses is Map ? poses.keys.toSet() : const <Object?>{};
  if (poseNames.isEmpty) problems.add('poses must be a non-empty object');
  problems.addAll(_keyProblems(data['keys'], poseNames, 'keys'));

  final gear = data['gear'];
  if (gear is! List) {
    problems.add('gear must be a list');
  } else {
    for (final use in gear) {
      final name = use is Map ? use['kit'] : null;
      final kit = kits[name];
      if (kit == null) {
        problems.add('gear names no kit $name');
      } else if (recipe.isApproved &&
          kit is Map &&
          kit['status'] != 'approved') {
        problems.add('approved, but kit $name is not');
      }
    }
  }

  final lines = _mistakeCount(exercise);
  final seen = <Object?>{};
  final mistakes = data['mistakes'] ?? const <Object?>[];
  if (mistakes is! List) {
    problems.add('mistakes must be a list');
    return problems;
  }
  for (final mistake in mistakes) {
    if (mistake is! Map<String, Object?>) {
      problems.add('a mistake is not an object');
      continue;
    }
    final line = mistake['line'];
    final where = 'mistake line $line';
    if (line is! int || line < 0 || line >= lines) {
      problems.add('$where is not one of the exercise\'s $lines mistakes');
    } else if (!seen.add(line)) {
      problems.add('$where appears twice');
    }
    if (mistake['shown'] == false) continue;
    if (!recipeStatuses.contains(mistake['status'])) {
      problems.add(
        '$where: status ${mistake['status']} is not one of '
        '${recipeStatuses.join(', ')}',
      );
    }
    final own = mistake['poses'];
    problems.addAll(
      _keyProblems(mistake['keys'] ?? data['keys'], {
        ...poseNames,
        if (own is Map) ...own.keys,
      }, '$where keys'),
    );
  }
  return problems;
}

/// The fewest `mistakes` lines in any of the exercise's languages.
int _mistakeCount(ExerciseEntry exercise) {
  final l10n = exercise.data['l10n'];
  if (l10n is! Map || l10n.isEmpty) return 0;
  return [
    for (final text in l10n.values)
      text is Map && text['mistakes'] is List
          ? (text['mistakes'] as List).length
          : 0,
  ].reduce((a, b) => a < b ? a : b);
}

/// `keys` are `[seconds, pose]` pairs naming [poses], from 0, ending on the
/// first pose so the loop does not jump.
List<String> _keyProblems(Object? keys, Set<Object?> poses, String where) {
  if (keys is! List || keys.isEmpty) return ['$where must be a non-empty list'];
  final problems = <String>[];
  for (final key in keys) {
    if (key is! List || key.length != 2 || key[0] is! num) {
      problems.add('$where: $key is not [seconds, pose]');
    } else if (!poses.contains(key[1])) {
      problems.add('$where: no pose ${key[1]}');
    }
  }
  if (problems.isNotEmpty) return problems;
  final first = keys.first as List, last = keys.last as List;
  return [
    if (first[0] != 0) '$where must start at 0',
    if (last[1] != first[1]) '$where must end on the first pose, ${first[1]}',
  ];
}
