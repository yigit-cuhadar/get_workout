import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';
import 'catalogue_program.dart';

/// The catalogue's filters. An empty set allows every value.
class CatalogueFilter extends Equatable {
  const CatalogueFilter({
    this.levels = const {},
    this.daysPerWeek = const {},
    this.goals = const {},
    this.profiles = const {},
    this.fitsMyEquipment = false,
  });

  final Set<Level> levels;
  final Set<int> daysPerWeek;
  final Set<Goal> goals;
  final Set<EquipmentProfile> profiles;

  /// Only programs [CatalogueProgram.fits] the user's equipment; neither
  /// applied nor active while that is unknown.
  final bool fitsMyEquipment;

  /// Whether the filter leaves anything out for someone owning [owned]
  /// (null while unknown).
  bool isActive(Set<Equipment>? owned) => activeCount(owned) > 0;

  /// The values chosen, each one filter, for someone owning [owned] (null
  /// while unknown).
  int activeCount(Set<Equipment>? owned) =>
      levels.length +
      daysPerWeek.length +
      goals.length +
      profiles.length +
      (fitsMyEquipment && owned != null ? 1 : 0);

  /// [owned] is the user's equipment, null when unknown.
  bool matches(CatalogueProgram program, Set<Equipment>? owned) =>
      (levels.isEmpty || levels.contains(program.level)) &&
      (daysPerWeek.isEmpty || daysPerWeek.contains(program.daysPerWeek)) &&
      (goals.isEmpty || goals.contains(program.goal)) &&
      (profiles.isEmpty || profiles.contains(program.equipmentProfile)) &&
      (!fitsMyEquipment || owned == null || program.fits(owned));

  CatalogueFilter copyWith({
    Set<Level>? levels,
    Set<int>? daysPerWeek,
    Set<Goal>? goals,
    Set<EquipmentProfile>? profiles,
    bool? fitsMyEquipment,
  }) => CatalogueFilter(
    levels: levels ?? this.levels,
    daysPerWeek: daysPerWeek ?? this.daysPerWeek,
    goals: goals ?? this.goals,
    profiles: profiles ?? this.profiles,
    fitsMyEquipment: fitsMyEquipment ?? this.fitsMyEquipment,
  );

  @override
  List<Object?> get props => [
    levels,
    daysPerWeek,
    goals,
    profiles,
    fitsMyEquipment,
  ];
}

/// What the recommendation knows of the user: the profile's answers, each
/// null while unanswered.
class TrainingProfile extends Equatable {
  const TrainingProfile({
    this.goal,
    this.level,
    this.daysPerWeek,
    this.equipment,
  });

  final Goal? goal;
  final Level? level;
  final int? daysPerWeek;
  final Set<Equipment>? equipment;

  /// Whether [program] is for the user's goal, level and days per week, all
  /// answered: the Fits you tag.
  bool suits(CatalogueProgram program) =>
      goal != null &&
      level != null &&
      daysPerWeek != null &&
      program.goal == goal &&
      program.level == level &&
      program.daysPerWeek == daysPerWeek;

  @override
  List<Object?> get props => [goal, level, daysPerWeek, equipment];
}

/// Why a program is recommended, shown with it.
enum MatchReason { goal, level, days, equipment }

class Recommendation extends Equatable {
  const Recommendation(this.program, this.reasons);

  final CatalogueProgram program;

  /// In [MatchReason] order.
  final List<MatchReason> reasons;

  @override
  List<Object?> get props => [program, reasons];
}

/// How many programs [recommendPrograms] returns at most.
const recommendedCount = 3;

/// The programs that suit [profile] best, at most [recommendedCount], by
/// score with ties in catalogue order.
///
/// A program is left out when its equipment profile is not the user's
/// equipment type ([EquipmentProfile.typeOf]), its level is more than one
/// step from theirs, or its days per week differ from theirs by more than
/// one. The rest score 3 for the user's goal (1 for a related one), 2 for
/// their level (1 for one level below), 2 for their days per week (1 for
/// a day more or fewer). An unanswered part leaves nothing out and scores
/// nothing.
List<Recommendation> recommendPrograms(
  List<CatalogueProgram> programs,
  TrainingProfile profile,
) {
  final owned = profile.equipment;
  final type = owned == null ? null : EquipmentProfile.typeOf(owned);
  final (goal, level, days) = (
    profile.goal,
    profile.level,
    profile.daysPerWeek,
  );
  final scored = <(int, Recommendation)>[];
  for (final program in programs) {
    if (type != null && program.equipmentProfile != type) continue;
    final levelGap = level == null ? null : program.level.index - level.index;
    if (levelGap != null && levelGap.abs() > 1) continue;
    final dayGap = days == null ? null : (program.daysPerWeek - days).abs();
    if (dayGap != null && dayGap > 1) continue;
    final score =
        switch (goal) {
          null => 0,
          _ when program.goal == goal => 3,
          final goal when _related(goal, program.goal) => 1,
          _ => 0,
        } +
        switch (levelGap) {
          0 => 2,
          -1 => 1,
          _ => 0,
        } +
        switch (dayGap) {
          0 => 2,
          1 => 1,
          _ => 0,
        };
    scored.add((
      score,
      Recommendation(program, [
        if (goal != null && program.goal == goal) MatchReason.goal,
        if (levelGap == 0) MatchReason.level,
        if (dayGap == 0) MatchReason.days,
        if (type != null) MatchReason.equipment,
      ]),
    ));
  }
  // Indexes break ties, keeping catalogue order.
  final ranked = scored.indexed.toList()
    ..sort((a, b) {
      final byScore = b.$2.$1.compareTo(a.$2.$1);
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
  return [
    for (final (_, (_, recommendation)) in ranked.take(recommendedCount))
      recommendation,
  ];
}

/// Goals one point apart: building muscle and getting stronger, losing fat
/// and general fitness.
bool _related(Goal a, Goal b) {
  final pair = {a, b};
  return pair.containsAll(const {Goal.buildMuscle, Goal.getStronger}) ||
      pair.containsAll(const {Goal.loseFat, Goal.generalFitness});
}
