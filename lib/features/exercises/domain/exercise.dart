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

/// An exercise of the shared catalogue (`exercises/{id}`).
class Exercise extends Equatable {
  /// Language every exercise has, used when the requested one is missing.
  static const fallbackLanguage = 'en';

  const Exercise({
    required this.id,
    required this.status,
    required this.loggingType,
    required this.mechanic,
    required this.laterality,
    required this.level,
    required this.force,
    required this.movementPattern,
    required this.position,
    this.grip,
    this.gripWidth,
    required this.equipment,
    this.equipmentAlternatives = const [],
    required this.mainMuscles,
    this.secondaryMuscles = const [],
    required this.family,
    required this.familyRank,
    this.pinnedAlternatives = const [],
    this.excludedAlternatives = const [],
    required this.defaultRestS,
    this.incrementKg,
    required this.popularity,
    required this.l10n,
    this.updatedAt,
  });

  final String id;
  final ExerciseStatus status;
  final LoggingType loggingType;
  final Mechanic mechanic;
  final Laterality laterality;
  final Level level;
  final Force force;
  final MovementPattern movementPattern;
  final Position position;
  final Grip? grip;
  final GripWidth? gripWidth;
  final List<Equipment> equipment;

  /// Other equipment sets the exercise can be done with instead.
  final List<List<Equipment>> equipmentAlternatives;
  final List<Muscle> mainMuscles;
  final List<Muscle> secondaryMuscles;

  /// Groups variations, e.g. `bench_press`.
  final String family;

  /// Easier to harder within [family].
  final int familyRank;
  final List<String> pinnedAlternatives;
  final List<String> excludedAlternatives;
  final int defaultRestS;

  /// Step for "add weight"; null when the exercise has no external load.
  final double? incrementKg;

  /// Lower sorts first.
  final int popularity;

  /// Text per language code; always has [fallbackLanguage].
  final Map<String, ExerciseText> l10n;

  /// Null for content that has not been stored in Firestore yet.
  final DateTime? updatedAt;

  /// The text in [language], or in [fallbackLanguage] when there is none.
  ExerciseText text(String language) =>
      l10n[language] ?? l10n[fallbackLanguage]!;

  @override
  List<Object?> get props => [
    id,
    status,
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
    updatedAt,
  ];
}
