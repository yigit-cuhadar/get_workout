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

/// The 18 muscle groups of the body model.
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

/// A kind of place to train, with the equipment it has. Onboarding offers
/// these as quick picks for the user's equipment, and every ready-made
/// program is written for one. [Equipment.bodyweight] is always available,
/// so no profile lists it.
enum EquipmentProfile implements Coded {
  fullGym('full_gym'),
  homeGym('home_gym'),
  dumbbells('dumbbells'),
  bodyweight('bodyweight'),
  bands('bands');

  const EquipmentProfile(this.code);
  @override
  final String code;

  Set<Equipment> get equipment => switch (this) {
    fullGym => Equipment.values.toSet()..remove(Equipment.bodyweight),
    // A barbell at home means a rack to squat and press from; the
    // vocabulary has no code for it.
    homeGym => const {
      Equipment.barbell,
      Equipment.plate,
      Equipment.dumbbell,
      Equipment.bench,
      Equipment.pullUpBar,
    },
    dumbbells => const {Equipment.dumbbell, Equipment.bench},
    bodyweight => const {Equipment.pullUpBar, Equipment.dipStation},
    bands => const {Equipment.resistanceBand},
  };

  /// Whether every code of an exercise's equipment [set] is available here.
  bool has(Iterable<String> set) {
    final codes = {
      Equipment.bodyweight.code,
      for (final e in equipment) e.code,
    };
    return set.every(codes.contains);
  }

  /// The preset whose equipment is exactly [owned]; null when none is.
  static EquipmentProfile? matching(Set<Equipment> owned) {
    for (final preset in values) {
      final equipment = preset.equipment;
      if (equipment.length == owned.length && owned.containsAll(equipment)) {
        return preset;
      }
    }
    return null;
  }

  /// The user's equipment type: the preset that is exactly [owned], else
  /// the most similar one, by the items both have over the items either
  /// has, so a preset with much more than [owned] scores low too (ties to
  /// the smaller preset, then the earlier one); bodyweight when none
  /// shares any. Bodyweight itself is always owned and never counts.
  static EquipmentProfile typeOf(Set<Equipment> owned) {
    if (matching(owned) case final preset?) return preset;
    final items = owned.difference(const {Equipment.bodyweight});
    var best = bodyweight;
    var (bestShared, bestUnion) = (0, 1);
    for (final preset in values) {
      final equipment = preset.equipment;
      final shared = equipment.where(items.contains).length;
      if (shared == 0) continue;
      final union = equipment.union(items).length;
      // shared / union compared without division.
      final byScore = (shared * bestUnion).compareTo(bestShared * union);
      if (byScore > 0 ||
          (byScore == 0 && equipment.length < best.equipment.length)) {
        best = preset;
        (bestShared, bestUnion) = (shared, union);
      }
    }
    return best;
  }
}

/// How good an exercise is for a generated program, judged among exercises
/// of its own equipment. Read only by the program generator.
enum GeneratorTier implements Coded {
  staple('staple'),
  standard('standard'),

  /// Only when nothing better fits.
  fallback('fallback'),
  never('never');

  const GeneratorTier(this.code);
  @override
  final String code;
}

/// What a slot of a generator template is for: its dose and its place in
/// the day.
enum SlotRole implements Coded {
  primary('primary'),
  secondary('secondary'),
  accessory('accessory'),
  core('core');

  const SlotRole(this.code);
  @override
  final String code;
}

/// A part of the body a user may mark as sensitive; the generator then
/// leaves out the exercises that stress it.
enum SensitiveArea implements Coded {
  shoulders('shoulders'),
  elbowsWrists('elbows_wrists'),
  lowerBack('lower_back'),
  hips('hips'),
  knees('knees');

  const SensitiveArea(this.code);
  @override
  final String code;
}

/// A part of the body the generator's user may focus on or leave out.
enum FocusArea implements Coded {
  chest('chest'),
  back('back'),
  shoulders('shoulders'),
  arms('arms'),
  core('core'),
  glutes('glutes'),
  legs('legs');

  const FocusArea(this.code);
  @override
  final String code;
}

/// What a generated program prefers to train with, when the user has both.
enum EquipmentStyle implements Coded {
  any('any'),
  machines('machines'),
  freeWeights('free_weights');

  const EquipmentStyle(this.code);
  @override
  final String code;
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
