import 'package:forge_core/forge_core.dart';

import '../../body/domain/body_entry.dart';
import '../../profile/domain/user_profile.dart';
import 'body_fat.dart';
import 'calculation.dart';
import 'calories.dart';

/// What the app already knows about the user's body, metric, for the
/// calculators to start from. Each value is null when unknown; each date is
/// the day a value from the body log was recorded, null for the profile's.
class KnownBodyValues extends Equatable {
  const KnownBodyValues({
    this.sex,
    this.ageYears,
    this.heightCm,
    this.weightKg,
    this.weightDate,
    this.neckCm,
    this.neckDate,
    this.waistCm,
    this.waistDate,
    this.abdomenCm,
    this.abdomenDate,
    this.hipCm,
    this.hipDate,
    this.bodyFatPercent,
    this.bodyFatDate,
    this.activity,
  });

  final Sex? sex;
  final int? ageYears;
  final double? heightCm;
  final double? weightKg;
  final DateTime? weightDate;
  final double? neckCm;
  final DateTime? neckDate;

  /// The waist at its narrowest and the abdomen at the navel: the body fat
  /// formula's waist for women and for men; see [navyWaistFor].
  final double? waistCm;
  final DateTime? waistDate;
  final double? abdomenCm;
  final DateTime? abdomenDate;
  final double? hipCm;
  final DateTime? hipDate;

  /// US Navy, from [sex], [heightCm] and the circumferences [sex] needs.
  final double? bodyFatPercent;

  /// The oldest of the circumferences' dates: the estimate is as recent as
  /// its oldest measurement.
  final DateTime? bodyFatDate;
  final ActivityLevel? activity;

  @override
  List<Object?> get props => [
    sex,
    ageYears,
    heightCm,
    weightKg,
    weightDate,
    neckCm,
    neckDate,
    waistCm,
    waistDate,
    abdomenCm,
    abdomenDate,
    hipCm,
    hipDate,
    bodyFatPercent,
    bodyFatDate,
    activity,
  ];

  /// The known measurement `navyWaist` names for [sex], with its date.
  ({double cm, DateTime? date})? navyWaistFor(Sex sex) => switch (sex) {
    Sex.male when abdomenCm != null => (cm: abdomenCm!, date: abdomenDate),
    Sex.female when waistCm != null => (cm: waistCm!, date: waistDate),
    _ => null,
  };
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
  BodyEntry? latest(double? Function(BodyEntry entry) value) {
    for (final entry in entries) {
      if (value(entry) != null) return entry;
    }
    return null;
  }

  BodyEntry? measured(BodyMeasurement? measurement) => measurement == null
      ? null
      : latest((entry) => entry.measurements[measurement]);

  final UserProfile(:sex, :heightCm, :birthYear, :daysPerWeek) = profile;
  final weighed = latest((entry) => entry.weightKg);
  final neck = measured(BodyMeasurement.neck);
  final waist = measured(BodyMeasurement.waist);
  final abdomen = measured(BodyMeasurement.abdomen);
  final hip = measured(BodyMeasurement.hips);
  final neckCm = neck?.measurements[BodyMeasurement.neck];
  final waistCm = waist?.measurements[BodyMeasurement.waist];
  final abdomenCm = abdomen?.measurements[BodyMeasurement.abdomen];
  final hipCm = hip?.measurements[BodyMeasurement.hips];
  // Which measurement is the formula's waist depends on the sex.
  final (navy, navyCm) = switch (sex) {
    Sex.male => (abdomen, abdomenCm),
    Sex.female => (waist, waistCm),
    null => (null, null),
  };
  final bodyFatPercent = _bodyFat(sex, heightCm, neckCm, navyCm, hipCm);
  return KnownBodyValues(
    sex: sex,
    ageYears: birthYear == null ? null : currentYear - birthYear,
    heightCm: heightCm,
    weightKg: weighed?.weightKg ?? profile.weightKg,
    weightDate: weighed?.date,
    neckCm: neckCm,
    neckDate: neck?.date,
    waistCm: waistCm,
    waistDate: waist?.date,
    abdomenCm: abdomenCm,
    abdomenDate: abdomen?.date,
    hipCm: hipCm,
    hipDate: hip?.date,
    bodyFatPercent: bodyFatPercent,
    bodyFatDate: bodyFatPercent == null
        ? null
        : [
            neck!.date,
            navy!.date,
            if (sex == Sex.female) hip!.date,
          ].reduce((a, b) => a.isBefore(b) ? a : b),
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
