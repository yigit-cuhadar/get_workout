import 'package:forge_core/forge_core.dart';

import '../../body/domain/body_entry.dart';
import '../../body/domain/entry_body_fat.dart';
import '../../profile/domain/user_profile.dart';
import 'body_fat.dart';
import 'calculation.dart';
import 'calories.dart';

/// What the app already knows about the user's body, metric, for the
/// calculators to start from. Each value is null when unknown.
class KnownBodyValues extends Equatable {
  const KnownBodyValues({
    this.sex,
    this.ageYears,
    this.heightCm,
    this.weightKg,
    this.neckCm,
    this.waistCm,
    this.hipCm,
    this.bodyFatPercent,
    this.activity,
  });

  final Sex? sex;
  final int? ageYears;
  final double? heightCm;
  final double? weightKg;
  final double? neckCm;

  /// The formula's waist, the measurement `navyWaist` names for [sex];
  /// unknown without a sex.
  final double? waistCm;
  final double? hipCm;

  /// US Navy, from [sex], [heightCm] and the circumferences.
  final double? bodyFatPercent;
  final ActivityLevel? activity;

  @override
  List<Object?> get props => [
    sex,
    ageYears,
    heightCm,
    weightKg,
    neckCm,
    waistCm,
    hipCm,
    bodyFatPercent,
    activity,
  ];
}

/// The known values from [profile] and [entries] (newest first). The weight
/// is the newest entry's that has one, else the profile's; each
/// circumference is the newest entry's that has it, so they may come from
/// different days.
KnownBodyValues knownBodyValues({
  required UserProfile profile,
  required List<BodyEntry> entries,
  required int currentYear,
}) {
  double? latest(BodyMeasurement measurement) {
    for (final entry in entries) {
      if (entry.measurements[measurement] case final cm?) return cm;
    }
    return null;
  }

  double? weightKg = profile.weightKg;
  for (final entry in entries) {
    if (entry.weightKg case final kg?) {
      weightKg = kg;
      break;
    }
  }
  final UserProfile(:sex, :heightCm, :birthYear, :daysPerWeek) = profile;
  final neckCm = latest(BodyMeasurement.neck);
  // Which measurement is the formula's waist depends on the sex.
  final waistCm = sex == null ? null : latest(navyWaist(sex));
  final hipCm = latest(BodyMeasurement.hips);
  return KnownBodyValues(
    sex: sex,
    ageYears: birthYear == null ? null : currentYear - birthYear,
    heightCm: heightCm,
    weightKg: weightKg,
    neckCm: neckCm,
    waistCm: waistCm,
    hipCm: hipCm,
    bodyFatPercent: _bodyFat(sex, heightCm, neckCm, waistCm, hipCm),
    activity: daysPerWeek == null ? null : activityFor(daysPerWeek),
  );
}

double? _bodyFat(
  Sex? sex,
  double? heightCm,
  double? neckCm,
  double? waistCm,
  double? hipCm,
) {
  if (sex == null || heightCm == null || neckCm == null || waistCm == null) {
    return null;
  }
  return switch (estimateBodyFat(
    sex: sex,
    heightCm: heightCm,
    neckCm: neckCm,
    waistCm: waistCm,
    hipCm: hipCm,
  )) {
    Calculated(:final value) => value,
    _ => null,
  };
}

/// The activity level of training [daysPerWeek] days, by the levels'
/// descriptions: light 1-3 days, moderate 3-5, hard 6-7.
ActivityLevel activityFor(int daysPerWeek) => switch (daysPerWeek) {
  <= 2 => ActivityLevel.light,
  <= 5 => ActivityLevel.moderate,
  _ => ActivityLevel.active,
};
