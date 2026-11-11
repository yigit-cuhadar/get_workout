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
  bool isActive(Set<Equipment>? owned) =>
      levels.isNotEmpty ||
      daysPerWeek.isNotEmpty ||
      goals.isNotEmpty ||
      profiles.isNotEmpty ||
      (fitsMyEquipment && owned != null);

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

/// The programs that suit [profile] best, at most [recommendedCount].
///
/// A program that needs equipment the user lacks, or is of a higher level
/// than theirs (beginner while unanswered), is never recommended. The rest
/// score 3 for the user's goal, 2 for their level, 2 for their days per
/// week and 1 for a day more or less; a program scoring nothing is left
/// out. With [freeFirst] (a user without premium) free programs come before
/// premium ones; within that, by score, ties in catalogue order.
List<Recommendation> recommendPrograms(
  List<CatalogueProgram> programs,
  TrainingProfile profile, {
  required bool freeFirst,
}) {
  final owned = profile.equipment;
  final level = profile.level;
  final ceiling = level ?? Level.beginner;
  final days = profile.daysPerWeek;
  final scored = <(int, Recommendation)>[];
  for (final program in programs) {
    if (owned != null && !program.fits(owned)) continue;
    if (program.level.index > ceiling.index) continue;
    final dayGap = days == null ? null : (program.daysPerWeek - days).abs();
    final reasons = [
      if (program.goal == profile.goal) MatchReason.goal,
      if (program.level == level) MatchReason.level,
      if (dayGap == 0) MatchReason.days,
    ];
    final score =
        (reasons.contains(MatchReason.goal) ? 3 : 0) +
        (reasons.contains(MatchReason.level) ? 2 : 0) +
        switch (dayGap) {
          0 => 2,
          1 => 1,
          _ => 0,
        };
    if (score == 0) continue;
    scored.add((
      score,
      Recommendation(program, [
        ...reasons,
        if (owned != null) MatchReason.equipment,
      ]),
    ));
  }
  int tier((int, Recommendation) entry) =>
      freeFirst && entry.$2.program.premium ? 1 : 0;
  // Indexes break ties, keeping catalogue order.
  final ranked = scored.indexed.toList()
    ..sort((a, b) {
      final byTier = tier(a.$2).compareTo(tier(b.$2));
      if (byTier != 0) return byTier;
      final byScore = b.$2.$1.compareTo(a.$2.$1);
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
  return [
    for (final (_, (_, recommendation)) in ranked.take(recommendedCount))
      recommendation,
  ];
}
