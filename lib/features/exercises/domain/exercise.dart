import 'package:forge_core/forge_core.dart';

import 'vocabulary.dart';

/// The text of an exercise in one language.
class ExerciseText extends Equatable {
  const ExerciseText({
    required this.name,
    this.aliases = const [],
    this.setup = const [],
    this.execution = const [],
    this.mistakes = const [],
    this.safety,
    this.cues = const [],
  });

  final String name;
  final List<String> aliases;
  final List<String> setup;
  final List<String> execution;
  final List<String> mistakes;
  final String? safety;
  final List<String> cues;

  @override
  List<Object?> get props => [
    name,
    aliases,
    setup,
    execution,
    mistakes,
    safety,
    cues,
  ];
}

/// An exercise: a live one of the shared catalogue (`exercises/{id}`), or
/// one the user made ([isCustom], `users/{uid}/customExercises/{id}`).
///
/// A custom exercise has only a name, a logging type, muscles, equipment and
/// a [note]; every catalogue-only field is null or empty, and its name is
/// stored under [fallbackLanguage], so it shows in every language.
class Exercise extends Equatable {
  /// Language every exercise has, used when the requested one is missing.
  static const fallbackLanguage = 'en';

  /// Starts the id of every custom exercise and of no catalogue exercise
  /// (those start with `ex_`), so an id alone tells which one it is.
  static const customIdPrefix = 'custom_';

  const Exercise({
    required this.id,
    required this.loggingType,
    required Mechanic this.mechanic,
    required Laterality this.laterality,
    required Level this.level,
    required Force this.force,
    required MovementPattern this.movementPattern,
    required Position this.position,
    this.grip,
    this.gripWidth,
    required this.equipment,
    this.equipmentAlternatives = const [],
    required this.mainMuscles,
    this.secondaryMuscles = const [],
    required String this.family,
    required int this.familyRank,
    this.pinnedAlternatives = const [],
    this.excludedAlternatives = const [],
    required int this.defaultRestS,
    this.incrementKg,
    required int this.popularity,
    required this.l10n,
  }) : note = null;

  /// A custom exercise named [name]; [id] starts with [customIdPrefix].
  Exercise.custom({
    required this.id,
    required String name,
    required this.loggingType,
    required this.mainMuscles,
    this.secondaryMuscles = const [],
    this.equipment = const [],
    this.note,
  }) : mechanic = null,
       laterality = null,
       level = null,
       force = null,
       movementPattern = null,
       position = null,
       grip = null,
       gripWidth = null,
       equipmentAlternatives = const [],
       family = null,
       familyRank = null,
       pinnedAlternatives = const [],
       excludedAlternatives = const [],
       defaultRestS = null,
       incrementKg = null,
       popularity = null,
       l10n = {fallbackLanguage: ExerciseText(name: name)};

  final String id;
  final LoggingType loggingType;

  /// The fields from here to [position] are null only for a custom exercise.
  final Mechanic? mechanic;
  final Laterality? laterality;
  final Level? level;
  final Force? force;
  final MovementPattern? movementPattern;
  final Position? position;
  final Grip? grip;
  final GripWidth? gripWidth;

  /// Empty only for a custom exercise whose equipment was not given.
  final List<Equipment> equipment;

  /// Other equipment sets the exercise can be done with instead.
  final List<List<Equipment>> equipmentAlternatives;
  final List<Muscle> mainMuscles;
  final List<Muscle> secondaryMuscles;

  /// Groups variations, e.g. `bench_press`. This and every field below
  /// but [l10n] and [note] is null or empty for a custom exercise.
  final String? family;

  /// Easier to harder within [family].
  final int? familyRank;
  final List<String> pinnedAlternatives;
  final List<String> excludedAlternatives;
  final int? defaultRestS;

  /// Step for "add weight"; null when the exercise has no external load.
  final double? incrementKg;

  /// Lower sorts first.
  final int? popularity;

  /// Text per language code; always has [fallbackLanguage].
  final Map<String, ExerciseText> l10n;

  /// The user's own note; only a custom exercise has one.
  final String? note;

  bool get isCustom => id.startsWith(customIdPrefix);

  /// The text in [language], or in [fallbackLanguage] when there is none.
  ExerciseText text(String language) =>
      l10n[language] ?? l10n[fallbackLanguage]!;

  @override
  List<Object?> get props => [
    id,
    loggingType,
    mechanic,
    laterality,
    level,
    force,
    movementPattern,
    position,
    grip,
    gripWidth,
    equipment,
    equipmentAlternatives,
    mainMuscles,
    secondaryMuscles,
    family,
    familyRank,
    pinnedAlternatives,
    excludedAlternatives,
    defaultRestS,
    incrementKg,
    popularity,
    l10n,
    note,
  ];
}
