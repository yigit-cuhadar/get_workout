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

  /// Values are typed to one decimal in the user's unit, so a limit shown
  /// in lb or inches (30 kg as 66.1 lb, 10 cm as 3.9 in) lies just outside
  /// it in metric. Half a shown step of the coarser unit is let through.
  static const _weightSlackKg = 0.05 * 0.45359237;
  static const _lengthSlackCm = 0.05 * 2.54;

  /// False for NaN.
  static bool weightKg(double kg) =>
      kg >= minWeightKg - _weightSlackKg && kg <= maxWeightKg + _weightSlackKg;

  static bool measurementCm(double cm) =>
      cm >= minMeasurementCm - _lengthSlackCm &&
      cm <= maxMeasurementCm + _lengthSlackCm;
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
