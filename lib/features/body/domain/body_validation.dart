import '../../profile/domain/user_profile.dart';
import 'body_entry.dart';

/// A reason an entry cannot be saved.
enum BodyIssue { empty, dateInFuture, weightOutOfRange, measurementOutOfRange }

abstract final class BodyLimits {
  /// The profile's weight range.
  static const minWeightKg = ProfileLimits.minWeightKg;
  static const maxWeightKg = ProfileLimits.maxWeightKg;

  /// Wide enough for a wrist-thin forearm and the largest waist.
  static const minMeasurementCm = 10.0;
  static const maxMeasurementCm = 250.0;

  /// False for NaN.
  static bool weightKg(double kg) => kg >= minWeightKg && kg <= maxWeightKg;

  static bool measurementCm(double cm) =>
      cm >= minMeasurementCm && cm <= maxMeasurementCm;
}

/// Everything wrong with [entry] as of [now]; empty when it can be saved.
Set<BodyIssue> validateBodyEntry(BodyEntry entry, {required DateTime now}) {
  final weight = entry.weightKg;
  return {
    if (entry.isEmpty) BodyIssue.empty,
    if (entry.date.isAfter(now)) BodyIssue.dateInFuture,
    if (weight != null && !BodyLimits.weightKg(weight))
      BodyIssue.weightOutOfRange,
    if (!entry.measurements.values.every(BodyLimits.measurementCm))
      BodyIssue.measurementOutOfRange,
  };
}
