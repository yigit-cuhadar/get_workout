import 'package:forge_core/forge_core.dart';

import '../../calculators/domain/body_fat.dart';
import '../../calculators/domain/calculation.dart';
import '../../profile/domain/user_profile.dart';
import 'body_entry.dart';

/// The measurement the US Navy body-fat formula calls the waist for [sex]:
/// it is taken at the navel for men, which is the abdomen here, and at its
/// narrowest for women, which is the waist here.
BodyMeasurement navyWaist(Sex sex) => switch (sex) {
  Sex.male => BodyMeasurement.abdomen,
  Sex.female => BodyMeasurement.waist,
};

/// The measurements the US Navy body-fat formula needs for [sex], besides
/// the height: the neck, the [navyWaist] and, for women, the hips.
Set<BodyMeasurement> bodyFatMeasurements(Sex sex) => {
  BodyMeasurement.neck,
  navyWaist(sex),
  if (sex == Sex.female) BodyMeasurement.hips,
};

/// The body fat of one entry's measurements, or why there is none. Never
/// stored: derived again whenever it is shown.
sealed class EntryBodyFat extends Equatable {
  const EntryBodyFat();

  /// The percentage, if there is one.
  double? get percent => null;
}

final class BodyFatPercent extends EntryBodyFat {
  const BodyFatPercent(this.value);
  final double value;

  @override
  double get percent => value;

  @override
  List<Object?> get props => [value];
}

/// The profile has no sex.
final class BodyFatNeedsSex extends EntryBodyFat {
  const BodyFatNeedsSex();

  @override
  List<Object?> get props => [];
}

/// The profile has no height.
final class BodyFatNeedsHeight extends EntryBodyFat {
  const BodyFatNeedsHeight();

  @override
  List<Object?> get props => [];
}

final class BodyFatNeedsMeasurements extends EntryBodyFat {
  const BodyFatNeedsMeasurements(this.missing);
  final Set<BodyMeasurement> missing;

  @override
  List<Object?> get props => [missing];
}

/// The formula rejects these values: one is outside its range, or the
/// result is impossible.
final class BodyFatOutOfRange extends EntryBodyFat {
  const BodyFatOutOfRange();

  @override
  List<Object?> get props => [];
}

/// The body fat of [measurements] (cm) for a person of [sex] and
/// [heightCm], checked in that order.
EntryBodyFat entryBodyFat(
  Map<BodyMeasurement, double> measurements, {
  required Sex? sex,
  required double? heightCm,
}) {
  if (sex == null) return const BodyFatNeedsSex();
  if (heightCm == null) return const BodyFatNeedsHeight();
  final missing = bodyFatMeasurements(sex)
      .difference(measurements.keys.toSet());
  if (missing.isNotEmpty) return BodyFatNeedsMeasurements(missing);
  final estimate = estimateBodyFat(
    sex: sex,
    heightCm: heightCm,
    neckCm: measurements[BodyMeasurement.neck]!,
    waistCm: measurements[navyWaist(sex)]!,
    hipCm: measurements[BodyMeasurement.hips],
  );
  return switch (estimate) {
    Calculated(:final value) => BodyFatPercent(value),
    OutOfRange() || Rejected() => const BodyFatOutOfRange(),
  };
}

/// Tracked until the user chooses their own: the standard set, plus what
/// body fat needs once the sex is known.
Set<BodyMeasurement> defaultTrackedMeasurements(Sex? sex) => {
  ...BodyMeasurement.standard,
  if (sex != null) ...bodyFatMeasurements(sex),
};

/// What a measurement day asks for: the set the user [chosen], else the
/// default for their [sex].
Set<BodyMeasurement> trackedMeasurements(
  Set<BodyMeasurement>? chosen,
  Sex? sex,
) => chosen ?? defaultTrackedMeasurements(sex);

/// [tracked] with every measurement body fat needs for [sex] added.
Set<BodyMeasurement> withBodyFat(Set<BodyMeasurement> tracked, Sex sex) => {
  ...tracked,
  ...bodyFatMeasurements(sex),
};

/// [tracked] without the measurements that are there only for body fat:
/// those [sex]'s estimate needs that are not in the standard set. Equal to
/// [tracked] when there are none, e.g. every one of them is standard.
Set<BodyMeasurement> withoutBodyFat(Set<BodyMeasurement> tracked, Sex sex) =>
    tracked.difference(
      bodyFatMeasurements(sex).difference(BodyMeasurement.standard),
    );

/// Whether body fat is tracked: it can be estimated (the sex and height
/// are known) and every measurement it needs is in [tracked]. Derived, never
/// stored.
bool tracksBodyFat(
  Set<BodyMeasurement> tracked, {
  required Sex? sex,
  required double? heightCm,
}) =>
    sex != null &&
    heightCm != null &&
    tracked.containsAll(bodyFatMeasurements(sex));
