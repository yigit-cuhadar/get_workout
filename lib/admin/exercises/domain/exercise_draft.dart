import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/content_rules.dart';
import '../../../features/exercises/domain/vocabulary.dart';

/// An exercise as the editor holds it: every field of `exercises/{id}` that
/// the panel manages, any of them possibly unset or invalid until the content
/// rules pass. The English text is the only language edited.
class ExerciseDraft extends Equatable {
  const ExerciseDraft({
    this.id = '',
    this.status = ExerciseStatus.draft,
    this.loggingType,
    this.mechanic,
    this.laterality,
    this.level,
    this.force,
    this.movementPattern,
    this.position,
    this.grip,
    this.gripWidth,
    this.equipment = const [],
    this.equipmentAlternatives = const [],
    this.mainMuscles = const [],
    this.secondaryMuscles = const [],
    this.family = '',
    this.familyRank,
    this.pinnedAlternatives = const [],
    this.excludedAlternatives = const [],
    this.defaultRestS,
    this.incrementKg,
    this.popularity,
    this.name = '',
    this.aliases = const [],
    this.setup = const [],
    this.execution = const [],
    this.mistakes = const [],
    this.safety,
    this.cues = const [],
  });

  /// Reads the content-file shape leniently: an unknown code or a value of
  /// the wrong type becomes unset, and the content rules then report it.
  factory ExerciseDraft.fromJson(Map<String, Object?> json) {
    final l10n = json['l10n'];
    final en = l10n is Map ? l10n[_language] : null;
    final text = en is Map ? en : const {};
    final alternatives = json['equipmentAlternatives'];
    return ExerciseDraft(
      id: _string(json['id']),
      status:
          ExerciseStatus.values.byCode(json['status']) ?? ExerciseStatus.draft,
      loggingType: LoggingType.values.byCode(json['loggingType']),
      mechanic: Mechanic.values.byCode(json['mechanic']),
      laterality: Laterality.values.byCode(json['laterality']),
      level: Level.values.byCode(json['level']),
      force: Force.values.byCode(json['force']),
      movementPattern: MovementPattern.values.byCode(json['movementPattern']),
      position: Position.values.byCode(json['position']),
      grip: Grip.values.byCode(json['grip']),
      gripWidth: GripWidth.values.byCode(json['gripWidth']),
      equipment: _codes(json['equipment'], Equipment.values),
      equipmentAlternatives: [
        if (alternatives is List)
          for (final set in alternatives) _codes(set, Equipment.values),
      ],
      mainMuscles: _codes(json['mainMuscles'], Muscle.values),
      secondaryMuscles: _codes(json['secondaryMuscles'], Muscle.values),
      family: _string(json['family']),
      familyRank: _int(json['familyRank']),
      pinnedAlternatives: _strings(json['pinnedAlternatives']),
      excludedAlternatives: _strings(json['excludedAlternatives']),
      defaultRestS: _int(json['defaultRestS']),
      incrementKg: switch (json['incrementKg']) {
        final num value => value.toDouble(),
        _ => null,
      },
      popularity: _int(json['popularity']),
      name: _string(text['name']),
      aliases: _strings(text['aliases']),
      setup: _strings(text['setup']),
      execution: _strings(text['execution']),
      mistakes: _strings(text['mistakes']),
      safety: switch (text['safety']) {
        final String value => value,
        _ => null,
      },
      cues: _strings(text['cues']),
    );
  }

  static const _language = 'en';

  final String id;
  final ExerciseStatus status;
  final LoggingType? loggingType;
  final Mechanic? mechanic;
  final Laterality? laterality;
  final Level? level;
  final Force? force;
  final MovementPattern? movementPattern;
  final Position? position;
  final Grip? grip;
  final GripWidth? gripWidth;
  final List<Equipment> equipment;
  final List<List<Equipment>> equipmentAlternatives;
  final List<Muscle> mainMuscles;
  final List<Muscle> secondaryMuscles;
  final String family;
  final int? familyRank;
  final List<String> pinnedAlternatives;
  final List<String> excludedAlternatives;
  final int? defaultRestS;
  final double? incrementKg;
  final int? popularity;
  final String name;
  final List<String> aliases;
  final List<String> setup;
  final List<String> execution;
  final List<String> mistakes;
  final String? safety;
  final List<String> cues;

  /// Whether [incrementKg] applies to the logging type.
  bool get takesIncrement => weightedLoggingTypes.contains(loggingType);

  /// The content-file shape the content rules check. Unset required fields
  /// are written as null so the rules report them; optional ones that are
  /// unset or empty are left out, as the content files leave them out.
  Map<String, Object?> toJson() => {
    'id': id,
    'status': status.code,
    'loggingType': loggingType?.code,
    'mechanic': mechanic?.code,
    'laterality': laterality?.code,
    'level': level?.code,
    'force': force?.code,
    'movementPattern': movementPattern?.code,
    'position': position?.code,
    if (grip != null) 'grip': grip!.code,
    if (gripWidth != null) 'gripWidth': gripWidth!.code,
    'equipment': _codesOf(equipment),
    if (equipmentAlternatives.isNotEmpty)
      'equipmentAlternatives': [
        for (final set in equipmentAlternatives) _codesOf(set),
      ],
    'mainMuscles': _codesOf(mainMuscles),
    'secondaryMuscles': _codesOf(secondaryMuscles),
    'family': family,
    'familyRank': familyRank,
    'pinnedAlternatives': [...pinnedAlternatives],
    'excludedAlternatives': [...excludedAlternatives],
    'defaultRestS': defaultRestS,
    if (incrementKg != null) 'incrementKg': incrementKg,
    'popularity': popularity,
    'l10n': {
      _language: {
        'name': name,
        'aliases': [...aliases],
        'setup': [...setup],
        'execution': [...execution],
        'mistakes': [...mistakes],
        if (safety != null && safety!.isNotEmpty) 'safety': safety,
        'cues': [...cues],
      },
    },
  };

  static const _unset = Object();

  /// Pass null to clear an optional field.
  ExerciseDraft copyWith({
    String? id,
    ExerciseStatus? status,
    Object? loggingType = _unset,
    Object? mechanic = _unset,
    Object? laterality = _unset,
    Object? level = _unset,
    Object? force = _unset,
    Object? movementPattern = _unset,
    Object? position = _unset,
    Object? grip = _unset,
    Object? gripWidth = _unset,
    List<Equipment>? equipment,
    List<List<Equipment>>? equipmentAlternatives,
    List<Muscle>? mainMuscles,
    List<Muscle>? secondaryMuscles,
    String? family,
    Object? familyRank = _unset,
    List<String>? pinnedAlternatives,
    List<String>? excludedAlternatives,
    Object? defaultRestS = _unset,
    Object? incrementKg = _unset,
    Object? popularity = _unset,
    String? name,
    List<String>? aliases,
    List<String>? setup,
    List<String>? execution,
    List<String>? mistakes,
    Object? safety = _unset,
    List<String>? cues,
  }) {
    T? pick<T>(Object? value, T? current) =>
        identical(value, _unset) ? current : value as T?;
    return ExerciseDraft(
      id: id ?? this.id,
      status: status ?? this.status,
      loggingType: pick(loggingType, this.loggingType),
      mechanic: pick(mechanic, this.mechanic),
      laterality: pick(laterality, this.laterality),
      level: pick(level, this.level),
      force: pick(force, this.force),
      movementPattern: pick(movementPattern, this.movementPattern),
      position: pick(position, this.position),
      grip: pick(grip, this.grip),
      gripWidth: pick(gripWidth, this.gripWidth),
      equipment: equipment ?? this.equipment,
      equipmentAlternatives:
          equipmentAlternatives ?? this.equipmentAlternatives,
      mainMuscles: mainMuscles ?? this.mainMuscles,
      secondaryMuscles: secondaryMuscles ?? this.secondaryMuscles,
      family: family ?? this.family,
      familyRank: pick(familyRank, this.familyRank),
      pinnedAlternatives: pinnedAlternatives ?? this.pinnedAlternatives,
      excludedAlternatives: excludedAlternatives ?? this.excludedAlternatives,
      defaultRestS: pick(defaultRestS, this.defaultRestS),
      incrementKg: pick(incrementKg, this.incrementKg),
      popularity: pick(popularity, this.popularity),
      name: name ?? this.name,
      aliases: aliases ?? this.aliases,
      setup: setup ?? this.setup,
      execution: execution ?? this.execution,
      mistakes: mistakes ?? this.mistakes,
      safety: pick(safety, this.safety),
      cues: cues ?? this.cues,
    );
  }

  static String _string(Object? value) => value is String ? value : '';

  static int? _int(Object? value) => value is int ? value : null;

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  static List<T> _codes<T extends Coded>(Object? value, List<T> values) => [
    if (value is List)
      for (final code in value) ?values.byCode(code),
  ];

  static List<String> _codesOf(List<Coded> values) => [
    for (final value in values) value.code,
  ];

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
    name,
    aliases,
    setup,
    execution,
    mistakes,
    safety,
    cues,
  ];
}

/// A stored `exercises/{id}` document as the panel reads it.
class ExerciseRecord extends Equatable {
  ExerciseRecord({required this.json, required this.updatedAt})
    : draft = ExerciseDraft.fromJson(json);

  /// The managed content in the content-file shape, with `id`; without
  /// `updatedAt` and `contentHash`, but with any unknown field.
  final Map<String, Object?> json;

  /// Null only while the server has not confirmed a write yet.
  final DateTime? updatedAt;

  final ExerciseDraft draft;

  String get id => draft.id;

  @override
  List<Object?> get props => [json, updatedAt];
}

/// How a save ended when Firestore was reached.
sealed class SaveOutcome extends Equatable {
  const SaveOutcome();

  @override
  List<Object?> get props => [];
}

final class Saved extends SaveOutcome {
  const Saved(this.record);

  /// The document as stored, with its new `updatedAt`.
  final ExerciseRecord record;

  @override
  List<Object?> get props => [record];
}

/// A new exercise's id is already used; nothing was written.
final class IdTaken extends SaveOutcome {
  const IdTaken();
}

/// The document changed since the editor loaded it; nothing was written.
final class ChangedSinceLoaded extends SaveOutcome {
  const ChangedSinceLoaded();
}
