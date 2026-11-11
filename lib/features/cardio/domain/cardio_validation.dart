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
  noteTooLong,
}

abstract final class CardioLimits {
  static const maxDuration = Duration(hours: 24);
  static const minDistanceKm = 0.01;
  static const maxDistanceKm = 500.0;
  static const maxCalories = 10000;
  static const minHeartRate = 30;
  static const maxHeartRate = 240;
  static const minIncline = -10.0;
  static const maxIncline = 40.0;
  static const maxNoteLength = 500;
}

/// Everything wrong with [session] as of [now]; empty when it can be saved.
/// Fields the session's type does not use are ignored. NaN and infinities
/// fail every range check.
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
        !_within(
          distance,
          CardioLimits.minDistanceKm,
          CardioLimits.maxDistanceKm,
        ))
      CardioIssue.distanceOutOfRange,
    if (calories != null && !_within(calories, 1, CardioLimits.maxCalories))
      CardioIssue.caloriesOutOfRange,
    if (heartRate != null &&
        !_within(
          heartRate,
          CardioLimits.minHeartRate,
          CardioLimits.maxHeartRate,
        ))
      CardioIssue.heartRateOutOfRange,
    if (type.incline &&
        incline != null &&
        !_within(incline, CardioLimits.minIncline, CardioLimits.maxIncline))
      CardioIssue.inclineOutOfRange,
    if ((session.note?.length ?? 0) > CardioLimits.maxNoteLength)
      CardioIssue.noteTooLong,
  };
}

/// False for NaN, whose comparisons are all false.
bool _within(num value, num min, num max) => value >= min && value <= max;
