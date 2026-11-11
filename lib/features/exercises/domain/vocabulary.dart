/// The stored vocabulary of an exercise (SPEC.md, "Vocabulary"). Every value
/// carries the string code it is stored as.
abstract interface class Coded {
  String get code;
}

extension CodedValues<T extends Coded> on List<T> {
  /// The value stored as [code], or null when [code] is not one of them.
  T? byCode(Object? code) {
    for (final value in this) {
      if (value.code == code) return value;
    }
    return null;
  }
}

enum LoggingType implements Coded {
  reps('reps'),
  weightReps('weight_reps'),
  weightedBodyweight('weighted_bodyweight'),
  assistedBodyweight('assisted_bodyweight'),
  duration('duration'),
  weightDuration('weight_duration');

  const LoggingType(this.code);
  @override
  final String code;
}

/// The 19 muscle groups of the body model.
enum Muscle implements Coded {
  pec('pec'),
  lat('lat'),
  trap('trap'),
  frontDelt('front_delt'),
  midDelt('mid_delt'),
  rearDelt('rear_delt'),
  biceps('biceps'),
  triceps('triceps'),
  forearm('forearm'),
  abdominal('abdominal'),
  oblique('oblique'),
  erector('erector'),
  glute('glute'),
  hipFlexor('hip_flexor'),
  abductor('abductor'),
  adductor('adductor'),
  quads('quads'),
  hamstring('hamstring'),
  calf('calf');

  const Muscle(this.code);
  @override
  final String code;
}

enum Equipment implements Coded {
  barbell('barbell'),
  ezBar('ez_bar'),
  trapBar('trap_bar'),
  dumbbell('dumbbell'),
  kettlebell('kettlebell'),
  plate('plate'),
  cable('cable'),
  machine('machine'),
  smithMachine('smith_machine'),
  bench('bench'),
  box('box'),
  backExtensionBench('back_extension_bench'),
  pullUpBar('pull_up_bar'),
  dipStation('dip_station'),
  resistanceBand('resistance_band'),
  suspensionTrainer('suspension_trainer'),
  rings('rings'),
  medicineBall('medicine_ball'),
  stabilityBall('stability_ball'),
  abWheel('ab_wheel'),
  landmine('landmine'),
  sled('sled'),
  jumpRope('jump_rope'),

  /// No equipment at all; always owned, and only ever listed alone.
  bodyweight('bodyweight'),
  other('other');

  const Equipment(this.code);
  @override
  final String code;
}

enum MovementPattern implements Coded {
  squat('squat'),
  hinge('hinge'),
  lunge('lunge'),
  horizontalPush('horizontal_push'),
  verticalPush('vertical_push'),
  horizontalPull('horizontal_pull'),
  verticalPull('vertical_pull'),
  carry('carry'),
  coreFlexion('core_flexion'),
  coreStability('core_stability'),
  rotation('rotation'),
  explosive('explosive'),
  isolation('isolation'),
  mobility('mobility');

  const MovementPattern(this.code);
  @override
  final String code;
}

enum Mechanic implements Coded {
  compound('compound'),
  isolation('isolation');

  const Mechanic(this.code);
  @override
  final String code;
}

enum Laterality implements Coded {
  bilateral('bilateral'),

  /// Logged once per set, meaning "per side".
  unilateral('unilateral'),
  alternating('alternating');

  const Laterality(this.code);
  @override
  final String code;
}

enum Level implements Coded {
  beginner('beginner'),
  intermediate('intermediate'),
  advanced('advanced');

  const Level(this.code);
  @override
  final String code;
}

enum Force implements Coded {
  push('push'),
  pull('pull'),
  static('static');

  const Force(this.code);
  @override
  final String code;
}

enum Position implements Coded {
  standing('standing'),
  seated('seated'),
  supine('supine'),
  prone('prone'),
  incline('incline'),
  decline('decline'),
  hanging('hanging'),

  /// On the arms: dips, L-sit, ring support.
  supported('supported'),

  /// Head down: handstands.
  inverted('inverted'),
  kneeling('kneeling'),
  sideLying('side_lying'),
  quadruped('quadruped');

  const Position(this.code);
  @override
  final String code;
}

enum Grip implements Coded {
  overhand('overhand'),
  underhand('underhand'),
  neutral('neutral'),
  mixed('mixed');

  const Grip(this.code);
  @override
  final String code;
}

enum GripWidth implements Coded {
  narrow('narrow'),
  shoulder('shoulder'),
  wide('wide');

  const GripWidth(this.code);
  @override
  final String code;
}

/// What a user trains for, and what a program is built for.
enum Goal implements Coded {
  buildMuscle('build_muscle'),
  getStronger('get_stronger'),
  loseFat('lose_fat'),
  generalFitness('general_fitness');

  const Goal(this.code);
  @override
  final String code;
}

/// The kind of place a ready-made program is written for, with the equipment
/// it has. An exercise fits a profile when its `equipment` or one of its
/// `equipmentAlternatives` sets is within [equipment].
enum EquipmentProfile implements Coded {
  /// Everything in [Equipment].
  fullGym('full_gym', null),
  homeGym('home_gym', {
    Equipment.barbell,
    Equipment.plate,
    Equipment.dumbbell,
    Equipment.bench,
    Equipment.pullUpBar,
    Equipment.resistanceBand,
    Equipment.bodyweight,
  }),
  dumbbells('dumbbells', {
    Equipment.dumbbell,
    Equipment.bench,
    Equipment.bodyweight,
  }),
  bodyweight('bodyweight', {
    Equipment.bodyweight,
    Equipment.pullUpBar,
    Equipment.dipStation,
  }),
  bands('bands', {Equipment.resistanceBand, Equipment.bodyweight});

  const EquipmentProfile(this.code, this._equipment);
  @override
  final String code;
  final Set<Equipment>? _equipment;

  Set<Equipment> get equipment => _equipment ?? Equipment.values.toSet();

  /// Whether every code of [set] is equipment of this profile.
  bool has(Iterable<String> set) {
    final codes = {for (final e in equipment) e.code};
    return set.every(codes.contains);
  }
}

/// Whether users see an exercise. Exercises are never deleted, only retired.
enum ExerciseStatus implements Coded {
  draft('draft'),
  live('live'),
  retired('retired');

  const ExerciseStatus(this.code);
  @override
  final String code;
}
