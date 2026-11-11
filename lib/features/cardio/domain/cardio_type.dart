/// What a cardio type shows next to its distance.
enum CardioRate {
  /// Time per distance unit, for activities on foot.
  pace,

  /// Distance per hour, for cycling.
  speed,

  /// Distance only.
  none,
}

/// A cardio activity. [code] is what Firestore stores. Each type declares
/// which optional fields make sense for it; calories and heart rate always do.
enum CardioType {
  treadmillRun('treadmill_run', distance: true, incline: true),
  treadmillWalk('treadmill_walk', distance: true, incline: true),
  outdoorRun('outdoor_run', distance: true),
  outdoorWalk('outdoor_walk', distance: true),
  hiking('hiking', distance: true),
  stationaryBike('stationary_bike', distance: true, rate: CardioRate.speed),
  outdoorCycle('outdoor_cycle', distance: true, rate: CardioRate.speed),
  elliptical('elliptical'),
  rowing('rowing', distance: true, rate: CardioRate.none),
  stairClimber('stair_climber', incline: true),
  swimming('swimming', distance: true, rate: CardioRate.none),
  jumpRope('jump_rope'),
  hiit('hiit'),
  other('other');

  const CardioType(
    this.code, {
    this.distance = false,
    this.incline = false,
    this.rate = CardioRate.pace,
  });

  final String code;
  final bool distance;
  final bool incline;

  /// Only meaningful when [distance] is true.
  final CardioRate rate;

  /// Unknown codes, e.g. from a newer app version, read as [other].
  static CardioType fromCode(Object? code) => values.firstWhere(
    (type) => type.code == code,
    orElse: () => CardioType.other,
  );
}
