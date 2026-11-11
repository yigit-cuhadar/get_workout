import 'package:forge_core/forge_core.dart';

import 'cardio_type.dart';

/// The unit distances are shown in. Everything is stored in km.
enum DistanceUnit {
  km(1),
  mile(1.609344);

  const DistanceUnit(this.kmPerUnit);
  final double kmPerUnit;

  double fromKm(double km) => km / kmPerUnit;
  double toKm(double value) => value * kmPerUnit;
}

/// One logged cardio session.
class CardioSession extends Equatable {
  const CardioSession({
    this.id,
    required this.type,
    required this.date,
    required this.duration,
    this.distanceKm,
    this.calories,
    this.avgHeartRate,
    this.incline,
    this.note,
  });

  /// Null until the session is stored.
  final String? id;
  final CardioType type;

  /// When the session started.
  final DateTime date;
  final Duration duration;
  final double? distanceKm;
  final int? calories;

  /// Beats per minute.
  final int? avgHeartRate;

  /// Percent grade.
  final double? incline;
  final String? note;

  /// Time per [unit] of distance; null without a distance.
  Duration? pace(DistanceUnit unit) {
    final distance = distanceKm;
    if (distance == null || distance <= 0) return null;
    return Duration(
      microseconds: (duration.inMicroseconds / unit.fromKm(distance)).round(),
    );
  }

  /// [unit]s per hour; null without a distance or duration.
  double? speed(DistanceUnit unit) {
    final distance = distanceKm;
    if (distance == null || duration <= Duration.zero) return null;
    return unit.fromKm(distance) /
        (duration.inMicroseconds / Duration.microsecondsPerHour);
  }

  CardioSession withId(String id) => CardioSession(
    id: id,
    type: type,
    date: date,
    duration: duration,
    distanceKm: distanceKm,
    calories: calories,
    avgHeartRate: avgHeartRate,
    incline: incline,
    note: note,
  );

  @override
  List<Object?> get props => [
    id,
    type,
    date,
    duration,
    distanceKm,
    calories,
    avgHeartRate,
    incline,
    note,
  ];
}
