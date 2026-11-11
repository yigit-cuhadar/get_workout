import 'cardio_session.dart';

/// A reason a session cannot be saved; each belongs to one form field.
enum CardioIssue {
  durationMissing,
  durationTooLong,
  dateInFuture,
  distanceOutOfRange,
  caloriesOutOfRange,
  heartRateOutOfRange,
  inclineOutOfRange,
}

abstract final class CardioLimits {
  static const maxDuration = Duration(hours: 24);
  static const maxDistanceKm = 500.0;
  static const maxCalories = 10000;
  static const minHeartRate = 30;
  static const maxHeartRate = 240;
  static const minIncline = -10.0;
  static const maxIncline = 40.0;
}

/// Everything wrong with [session] as of [now]; empty when it can be saved.
/// Fields the session's type does not use are ignored.
Set<CardioIssue> validateCardio(
  CardioSession session, {
  required DateTime now,
}) {
  final type = session.type;
  final distance = session.distanceKm;
  final calories = session.calories;
  final heartRate = session.avgHeartRate;
  final incline = session.incline;
  return {
    if (session.duration <= Duration.zero) CardioIssue.durationMissing,
    if (session.duration > CardioLimits.maxDuration)
      CardioIssue.durationTooLong,
    if (session.date.isAfter(now)) CardioIssue.dateInFuture,
    if (type.distance &&
        distance != null &&
        (distance <= 0 || distance > CardioLimits.maxDistanceKm))
      CardioIssue.distanceOutOfRange,
    if (calories != null &&
        (calories <= 0 || calories > CardioLimits.maxCalories))
      CardioIssue.caloriesOutOfRange,
    if (heartRate != null &&
        (heartRate < CardioLimits.minHeartRate ||
            heartRate > CardioLimits.maxHeartRate))
      CardioIssue.heartRateOutOfRange,
    if (type.incline &&
        incline != null &&
        (incline < CardioLimits.minIncline ||
            incline > CardioLimits.maxIncline))
      CardioIssue.inclineOutOfRange,
  };
}
