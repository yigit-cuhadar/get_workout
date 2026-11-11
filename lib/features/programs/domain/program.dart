import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';

/// Where a user's program came from. Only [own] is created by the builder.
enum ProgramOrigin implements Coded {
  own('own'),
  catalog('catalog'),
  generated('generated');

  const ProgramOrigin(this.code);
  @override
  final String code;
}

/// Name lengths count UTF-16 code units ([String.length]) everywhere: the
/// text fields, validation and the rules' limits, which count no more.
abstract final class ProgramLimits {
  static const maxNameLength = 60;
  static const maxDayNameLength = 40;
  static const maxDays = 7;
  static const maxItemsPerDay = 20;
  static const minLengthWeeks = 1;
  static const maxLengthWeeks = 52;
  static const minSets = 1;
  static const maxSets = 10;
  static const minReps = 1;
  static const maxReps = 100;
  static const minDurationS = 5;
  static const maxDurationS = 3600;
  static const maxRestS = 600;
  static const maxTargetKg = 1000.0;
}

/// What a program item asks for, by the exercise's logging type.
extension LoggingTypeTargets on LoggingType {
  /// Duration types take a duration; all others a rep range.
  bool get isDurationBased =>
      this == LoggingType.duration || this == LoggingType.weightDuration;

  /// The types that log a weight (added, or assistance) can have a target.
  bool get logsWeight =>
      this != LoggingType.reps && this != LoggingType.duration;
}

/// One exercise of a program day. Rep-based exercises use [repMin] and
/// [repMax], duration-based ones [durationS]; see [LoggingTypeTargets].
class ProgramItem extends Equatable {
  const ProgramItem({
    required this.exerciseId,
    required this.sets,
    this.repMin,
    this.repMax,
    this.durationS,
    required this.restS,
    this.targetKg,
    this.group,
    this.extra = const {},
  });

  final String exerciseId;
  final int sets;
  final int? repMin;
  final int? repMax;
  final int? durationS;

  /// Rest after each set; in a group, after each round.
  final int restS;
  final double? targetKg;

  /// Items of a day sharing this letter, always adjacent, form a superset
  /// (two) or a circuit (three or more).
  final String? group;

  /// Stored fields this app version does not know, written back unchanged.
  final Map<String, Object?> extra;

  ProgramItem copyWith({
    String? exerciseId,
    int? sets,
    int? Function()? repMin,
    int? Function()? repMax,
    int? Function()? durationS,
    int? restS,
    double? Function()? targetKg,
    String? Function()? group,
  }) => ProgramItem(
    exerciseId: exerciseId ?? this.exerciseId,
    sets: sets ?? this.sets,
    repMin: repMin != null ? repMin() : this.repMin,
    repMax: repMax != null ? repMax() : this.repMax,
    durationS: durationS != null ? durationS() : this.durationS,
    restS: restS ?? this.restS,
    targetKg: targetKg != null ? targetKg() : this.targetKg,
    group: group != null ? group() : this.group,
    extra: extra,
  );

  @override
  List<Object?> get props => [
    exerciseId,
    sets,
    repMin,
    repMax,
    durationS,
    restS,
    targetKg,
    group,
    extra,
  ];
}

class ProgramDay extends Equatable {
  const ProgramDay({
    this.name = '',
    this.items = const [],
    this.extra = const {},
  });

  /// May be blank; the app then shows "Day n".
  final String name;
  final List<ProgramItem> items;

  /// See [ProgramItem.extra].
  final Map<String, Object?> extra;

  ProgramDay copyWith({String? name, List<ProgramItem>? items}) => ProgramDay(
    name: name ?? this.name,
    items: items ?? this.items,
    extra: extra,
  );

  @override
  List<Object?> get props => [name, items, extra];
}

/// One of the user's programs (`users/{uid}/programs/{id}`).
class Program extends Equatable {
  const Program({
    this.id,
    required this.name,
    this.origin = ProgramOrigin.own,
    this.sourceId,
    this.lengthWeeks,
    required this.days,
  });

  /// Null until the program is stored.
  final String? id;
  final String name;
  final ProgramOrigin origin;

  /// The catalog program this one was copied from.
  final String? sourceId;

  /// Null for a program that runs until it is stopped.
  final int? lengthWeeks;
  final List<ProgramDay> days;

  Program copyWith({
    String? name,
    int? Function()? lengthWeeks,
    List<ProgramDay>? days,
  }) => Program(
    id: id,
    name: name ?? this.name,
    origin: origin,
    sourceId: sourceId,
    lengthWeeks: lengthWeeks != null ? lengthWeeks() : this.lengthWeeks,
    days: days ?? this.days,
  );

  /// A new program of the user's own with this one's content, named
  /// [nameOf] this one's name, e.g. "Push (copy)". Characters come off the
  /// end of the name until the copy's name fits the limit and differs from
  /// this one's.
  Program duplicate(String Function(String name) nameOf) {
    var base = name.trim();
    var copyName = nameOf(base);
    while ((copyName.length > ProgramLimits.maxNameLength ||
            copyName == name) &&
        base.isNotEmpty) {
      base = dropLastCharacter(base).trimRight();
      copyName = nameOf(base);
    }
    return Program(
      name: copyName.length > ProgramLimits.maxNameLength
          ? cutToLength(copyName, ProgramLimits.maxNameLength)
          : copyName,
      lengthWeeks: lengthWeeks,
      days: days,
    );
  }

  @override
  List<Object?> get props => [id, name, origin, sourceId, lengthWeeks, days];
}

/// [text] without its last character; never half of a surrogate pair.
String dropLastCharacter(String text) {
  if (text.isEmpty) return text;
  final runes = text.runes.toList()..removeLast();
  return String.fromCharCodes(runes);
}

/// [text] cut to at most [max] code units, without splitting a surrogate
/// pair.
String cutToLength(String text, int max) {
  var cut = text;
  while (cut.length > max) {
    cut = dropLastCharacter(cut);
  }
  return cut;
}
