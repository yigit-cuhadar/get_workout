import 'package:forge_core/forge_core.dart';

import 'exercise.dart';
import 'vocabulary.dart';

extension ExerciseEquipment on Exercise {
  /// Whether [owned] covers [Exercise.equipment] or one of the
  /// [Exercise.equipmentAlternatives] sets. Bodyweight is always owned.
  bool isDoableWith(Set<Equipment> owned) {
    bool covered(List<Equipment> set) => set.every(
      (item) => item == Equipment.bodyweight || owned.contains(item),
    );
    return covered(equipment) || equipmentAlternatives.any(covered);
  }
}

/// The [exercises] whose name or an alias contains [query], ignoring case,
/// diacritics, spaces and punctuation ("push up" finds "Push-Up"). Names that
/// start with the query come first, then by popularity. A blank query
/// returns [exercises] unchanged.
List<Exercise> searchExercises(
  Iterable<Exercise> exercises,
  String query, {
  required String language,
}) {
  final needle = _foldForSearch(query);
  if (needle.isEmpty) return exercises.toList();
  final prefix = <Exercise>[];
  final other = <Exercise>[];
  for (final exercise in exercises) {
    final text = exercise.text(language);
    final name = _foldForSearch(text.name);
    if (name.startsWith(needle)) {
      prefix.add(exercise);
    } else if (name.contains(needle) ||
        text.aliases.any((alias) => _foldForSearch(alias).contains(needle))) {
      other.add(exercise);
    }
  }
  return [
    ...prefix..sort(compareByPopularity),
    ...other..sort(compareByPopularity),
  ];
}

/// What the library shows. Within one criterion any selected value matches;
/// every criterion must match. Empty selections match everything.
class ExerciseFilter extends Equatable {
  const ExerciseFilter({
    this.muscles = const {},
    this.mainMusclesOnly = false,
    this.equipment = const {},
    this.levels = const {},
    this.movementPatterns = const {},
    this.doableWith,
  });

  /// Matched against main and secondary muscles, or main only with
  /// [mainMusclesOnly].
  final Set<Muscle> muscles;
  final bool mainMusclesOnly;

  /// Matched against [Exercise.equipment] only, not the alternative sets, so
  /// "dumbbell" lists dumbbell exercises.
  final Set<Equipment> equipment;
  final Set<Level> levels;
  final Set<MovementPattern> movementPatterns;

  /// The user's equipment when only doable exercises should show; null shows
  /// all.
  final Set<Equipment>? doableWith;

  bool matches(Exercise exercise) {
    final worked = mainMusclesOnly
        ? exercise.mainMuscles
        : [...exercise.mainMuscles, ...exercise.secondaryMuscles];
    final owned = doableWith;
    return (muscles.isEmpty || worked.any(muscles.contains)) &&
        (equipment.isEmpty || exercise.equipment.any(equipment.contains)) &&
        (levels.isEmpty || levels.contains(exercise.level)) &&
        (movementPatterns.isEmpty ||
            movementPatterns.contains(exercise.movementPattern)) &&
        (owned == null || exercise.isDoableWith(owned));
  }

  @override
  List<Object?> get props => [
    muscles,
    mainMusclesOnly,
    equipment,
    levels,
    movementPatterns,
    doableWith,
  ];
}

List<Exercise> filterExercises(
  Iterable<Exercise> exercises,
  ExerciseFilter filter,
) => exercises.where(filter.matches).toList();

enum ExerciseSort { popularity, alphabetical }

List<Exercise> sortExercises(
  Iterable<Exercise> exercises,
  ExerciseSort sort, {
  required String language,
}) {
  final sorted = exercises.toList();
  switch (sort) {
    case ExerciseSort.popularity:
      sorted.sort(compareByPopularity);
    case ExerciseSort.alphabetical:
      final keys = {
        for (final exercise in sorted)
          exercise.id: _foldCase(exercise.text(language).name),
      };
      sorted.sort((a, b) {
        final byName = keys[a.id]!.compareTo(keys[b.id]!);
        return byName != 0 ? byName : compareByPopularity(a, b);
      });
  }
  return sorted;
}

/// What to suggest instead of [exercise]: its pinned alternatives in their
/// order, then the exercises sharing a main muscle and its movement pattern,
/// those doable with [owned] first, then by popularity. Excluded ones never
/// show, even when also pinned.
List<Exercise> alternativesFor(
  Exercise exercise,
  Iterable<Exercise> catalogue, {
  required Set<Equipment> owned,
}) {
  final byId = {for (final other in catalogue) other.id: other};
  final skip = {exercise.id, ...exercise.excludedAlternatives};
  final pinned = [
    for (final id in exercise.pinnedAlternatives)
      if (!skip.contains(id) && byId[id] != null) byId[id]!,
  ];
  skip.addAll(exercise.pinnedAlternatives);
  final computed = [
    for (final other in byId.values)
      if (!skip.contains(other.id) &&
          other.movementPattern == exercise.movementPattern &&
          other.mainMuscles.any(exercise.mainMuscles.contains))
        other,
  ];
  final doable = {
    for (final other in computed)
      if (other.isDoableWith(owned)) other.id,
  };
  computed.sort((a, b) {
    final aDoable = doable.contains(a.id);
    if (aDoable != doable.contains(b.id)) return aDoable ? -1 : 1;
    return compareByPopularity(a, b);
  });
  return [...pinned, ...computed];
}

/// The other exercises of [exercise]'s family, easier to harder.
List<Exercise> variationsOf(Exercise exercise, Iterable<Exercise> catalogue) =>
    [
      for (final other in catalogue)
        if (other.family == exercise.family && other.id != exercise.id) other,
    ]..sort((a, b) {
      final byRank = a.familyRank.compareTo(b.familyRank);
      return byRank != 0 ? byRank : compareByPopularity(a, b);
    });

/// Popularity, then id so equal popularity still sorts the same every time.
int compareByPopularity(Exercise a, Exercise b) {
  final byPopularity = a.popularity.compareTo(b.popularity);
  return byPopularity != 0 ? byPopularity : a.id.compareTo(b.id);
}

/// [text] lowercased, without diacritics, spaces or punctuation.
String _foldForSearch(String text) =>
    _foldCase(text).replaceAll(_notLetterOrDigit, '');

final _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// [text] lowercased and without diacritics, precomposed or combining.
String _foldCase(String text) {
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    buffer.write(_plainLetters[char] ?? char);
  }
  return buffer.toString().replaceAll(_combiningMark, '');
}

final _combiningMark = RegExp(r'\p{M}', unicode: true);

final _plainLetters = {
  for (final MapEntry(key: plain, value: accented) in const {
    'a': 'àáâãäåāăą',
    'c': 'çćĉċč',
    'd': 'ďđð',
    'e': 'èéêëēĕėęě',
    'g': 'ĝğġģ',
    'h': 'ĥħ',
    'i': 'ìíîïĩīĭįı',
    'j': 'ĵ',
    'k': 'ķ',
    'l': 'ĺļľŀł',
    'n': 'ñńņňŉ',
    'o': 'òóôõöøōŏő',
    'r': 'ŕŗř',
    's': 'śŝşšș',
    't': 'ţťŧț',
    'u': 'ùúûüũūŭůűų',
    'w': 'ŵ',
    'y': 'ýÿŷ',
    'z': 'źżž',
    'ss': 'ß',
    'ae': 'æ',
    'oe': 'œ',
    'th': 'þ',
  }.entries)
    for (final char in accented.split('')) char: plain,
};

/// The exercises of a muscle, as the muscle sheet lists them.
typedef MuscleExercises = ({List<Exercise> main, List<Exercise> alsoWorks});

/// The [catalogue]'s exercises working [muscle]: [MuscleExercises.main] has
/// it as a main muscle, [MuscleExercises.alsoWorks] only as a secondary one.
/// Each by popularity.
MuscleExercises exercisesWorking(Muscle muscle, Iterable<Exercise> catalogue) {
  final main = <Exercise>[];
  final alsoWorks = <Exercise>[];
  for (final exercise in catalogue) {
    if (exercise.mainMuscles.contains(muscle)) {
      main.add(exercise);
    } else if (exercise.secondaryMuscles.contains(muscle)) {
      alsoWorks.add(exercise);
    }
  }
  return (
    main: main..sort(compareByPopularity),
    alsoWorks: alsoWorks..sort(compareByPopularity),
  );
}
