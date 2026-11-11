import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';

export '../../exercises/domain/vocabulary.dart' show Goal;

/// The two sexes the calorie (Mifflin-St Jeor) and body-fat (US Navy)
/// formulas define.
enum Sex implements Coded {
  male('male'),
  female('female');

  const Sex(this.code);
  @override
  final String code;
}

/// The answers of the profile, in the order onboarding asks them.
enum ProfileField {
  goal,
  level,
  daysPerWeek,
  equipment,
  sex,
  birthYear,
  height,
  weight,
  targetWeight;

  /// A personal question: onboarding lets the user skip it on its own, and
  /// editing may clear it. The others need an answer to continue.
  bool get optional => switch (this) {
    sex || birthYear || height || weight || targetWeight => true,
    goal || level || daysPerWeek || equipment => false,
  };
}

/// Quick picks that fill the equipment answer; it can be fine-tuned after.
enum EquipmentPreset {
  fullGym,
  homeGym,
  dumbbellsOnly,
  bodyweight;

  Set<Equipment> get equipment => switch (this) {
    fullGym => Equipment.values.toSet()..remove(Equipment.bodyweight),
    homeGym => const {
      Equipment.barbell,
      Equipment.dumbbell,
      Equipment.plate,
      Equipment.bench,
      Equipment.pullUpBar,
      Equipment.resistanceBand,
    },
    dumbbellsOnly => const {Equipment.dumbbell},
    bodyweight => const {},
  };
}

/// Sane ranges of the answers. Weights and lengths are metric.
abstract final class ProfileLimits {
  static const minDaysPerWeek = 2;
  static const maxDaysPerWeek = 6;
  static const minAge = 13;
  static const maxAge = 100;
  static const minHeightCm = 100.0;
  static const maxHeightCm = 250.0;
  static const minWeightKg = 30.0;
  static const maxWeightKg = 300.0;

  static bool daysPerWeek(int days) =>
      days >= minDaysPerWeek && days <= maxDaysPerWeek;

  /// The age is counted in whole years from the birth year alone.
  static bool birthYear(int year, {required int currentYear}) {
    final age = currentYear - year;
    return age >= minAge && age <= maxAge;
  }

  static bool heightCm(double cm) => cm >= minHeightCm && cm <= maxHeightCm;

  /// Also the range of the target weight.
  static bool weightKg(double kg) => kg >= minWeightKg && kg <= maxWeightKg;
}

/// What the user told us about themselves. Every answer is optional until
/// given; [onboardingCompletedAt] is set once onboarding is finished or
/// skipped.
class UserProfile extends Equatable {
  const UserProfile({
    this.goal,
    this.level,
    this.daysPerWeek,
    this.equipment,
    this.sex,
    this.birthYear,
    this.heightCm,
    this.weightKg,
    this.targetWeightKg,
    this.onboardingCompletedAt,
  });

  final Goal? goal;
  final Level? level;
  final int? daysPerWeek;

  /// Owned equipment. Never contains [Equipment.bodyweight], which everyone
  /// has; an empty set means bodyweight only.
  final Set<Equipment>? equipment;
  final Sex? sex;
  final int? birthYear;
  final double? heightCm;
  final double? weightKg;
  final double? targetWeightKg;
  final DateTime? onboardingCompletedAt;

  bool get onboardingCompleted => onboardingCompletedAt != null;

  bool answered(ProfileField field) => switch (field) {
    ProfileField.goal => goal != null,
    ProfileField.level => level != null,
    ProfileField.daysPerWeek => daysPerWeek != null,
    ProfileField.equipment => equipment != null,
    ProfileField.sex => sex != null,
    ProfileField.birthYear => birthYear != null,
    ProfileField.height => heightCm != null,
    ProfileField.weight => weightKg != null,
    ProfileField.targetWeight => targetWeightKg != null,
  };

  UserProfile copyWith({
    Goal? goal,
    Level? level,
    int? daysPerWeek,
    Set<Equipment>? equipment,
    Sex? sex,
    int? birthYear,
    double? heightCm,
    double? weightKg,
    double? targetWeightKg,
  }) => UserProfile(
    goal: goal ?? this.goal,
    level: level ?? this.level,
    daysPerWeek: daysPerWeek ?? this.daysPerWeek,
    equipment: equipment == null
        ? this.equipment
        : (equipment.toSet()..remove(Equipment.bodyweight)),
    sex: sex ?? this.sex,
    birthYear: birthYear ?? this.birthYear,
    heightCm: heightCm ?? this.heightCm,
    weightKg: weightKg ?? this.weightKg,
    targetWeightKg: targetWeightKg ?? this.targetWeightKg,
    onboardingCompletedAt: onboardingCompletedAt,
  );

  /// This profile with [field] unanswered.
  UserProfile without(ProfileField field) => UserProfile(
    goal: field == ProfileField.goal ? null : goal,
    level: field == ProfileField.level ? null : level,
    daysPerWeek: field == ProfileField.daysPerWeek ? null : daysPerWeek,
    equipment: field == ProfileField.equipment ? null : equipment,
    sex: field == ProfileField.sex ? null : sex,
    birthYear: field == ProfileField.birthYear ? null : birthYear,
    heightCm: field == ProfileField.height ? null : heightCm,
    weightKg: field == ProfileField.weight ? null : weightKg,
    targetWeightKg: field == ProfileField.targetWeight ? null : targetWeightKg,
    onboardingCompletedAt: onboardingCompletedAt,
  );

  @override
  List<Object?> get props => [
    goal,
    level,
    daysPerWeek,
    equipment,
    sex,
    birthYear,
    heightCm,
    weightKg,
    targetWeightKg,
    onboardingCompletedAt,
  ];
}
