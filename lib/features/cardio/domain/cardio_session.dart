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

/// The optional fields of a session; a partial update names the ones it
/// writes.
enum CardioField { distanceKm, calories, avgHeartRate, incline, note }

/// One logged cardio session.
class CardioSession extends Equatable {
  /// [typeCode] is the stored code when it is none of [CardioType]'s, so a
  /// newer app version's type survives an edit here; otherwise [type]'s.
  CardioSession({
    this.id,
    required CardioType type,
    String? typeCode,
    required this.date,
    required this.duration,
    this.distanceKm,
    this.calories,
    this.avgHeartRate,
    this.incline,
    this.note,
  }) : typeCode = typeCode ?? type.code;

  /// Null until the session is stored.
  final String? id;
  final String typeCode;

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

  /// Unknown codes read as [CardioType.other].
  CardioType get type => CardioType.fromCode(typeCode);

  /// Time per [unit] of distance; null without a usable distance.
  Duration? pace(DistanceUnit unit) {
    final distance = distanceKm;
    if (distance == null || distance <= 0) return null;
    final micros = duration.inMicroseconds / unit.fromKm(distance);
    // Bounded so the rounding below never overflows or sees NaN.
    if (!micros.isFinite || micros > _maxPaceMicros) return null;
    return Duration(microseconds: micros.round());
  }

  static const _maxPaceMicros = 1000 * Duration.microsecondsPerDay;

  /// [unit]s per hour; null without a usable distance and duration.
  double? speed(DistanceUnit unit) {
    final distance = distanceKm;
    if (distance == null || duration <= Duration.zero) return null;
    final speed =
        unit.fromKm(distance) /
        (duration.inMicroseconds / Duration.microsecondsPerHour);
    return speed.isFinite ? speed : null;
  }

  CardioSession withId(String id) => CardioSession(
    id: id,
    type: type,
    typeCode: typeCode,
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
    typeCode,
    date,
    duration,
    distanceKm,
    calories,
    avgHeartRate,
    incline,
    note,
  ];
}
