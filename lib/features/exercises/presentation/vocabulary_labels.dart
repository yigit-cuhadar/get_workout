import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/exercise.dart';
import '../domain/vocabulary.dart';

/// Display names of the stored vocabulary.
extension VocabularyLabels on AppLocalizations {
  String muscleName(Muscle muscle) => switch (muscle) {
    Muscle.pec => musclePec,
    Muscle.lat => muscleLat,
    Muscle.trap => muscleTrap,
    Muscle.frontDelt => muscleFrontDelt,
    Muscle.midDelt => muscleMidDelt,
    Muscle.rearDelt => muscleRearDelt,
    Muscle.biceps => muscleBiceps,
    Muscle.triceps => muscleTriceps,
    Muscle.forearm => muscleForearm,
    Muscle.abdominal => muscleAbdominal,
    Muscle.oblique => muscleOblique,
    Muscle.erector => muscleErector,
    Muscle.glute => muscleGlute,
    Muscle.hipFlexor => muscleHipFlexor,
    Muscle.abductor => muscleAbductor,
    Muscle.adductor => muscleAdductor,
    Muscle.quads => muscleQuads,
    Muscle.hamstring => muscleHamstring,
    Muscle.calf => muscleCalf,
  };

  String equipmentName(Equipment equipment) => switch (equipment) {
    Equipment.barbell => equipmentBarbell,
    Equipment.ezBar => equipmentEzBar,
    Equipment.trapBar => equipmentTrapBar,
    Equipment.dumbbell => equipmentDumbbell,
    Equipment.kettlebell => equipmentKettlebell,
    Equipment.plate => equipmentPlate,
    Equipment.cable => equipmentCable,
    Equipment.machine => equipmentMachine,
    Equipment.smithMachine => equipmentSmithMachine,
    Equipment.bench => equipmentBench,
    Equipment.box => equipmentBox,
    Equipment.backExtensionBench => equipmentBackExtensionBench,
    Equipment.pullUpBar => equipmentPullUpBar,
    Equipment.dipStation => equipmentDipStation,
    Equipment.resistanceBand => equipmentResistanceBand,
    Equipment.suspensionTrainer => equipmentSuspensionTrainer,
    Equipment.rings => equipmentRings,
    Equipment.medicineBall => equipmentMedicineBall,
    Equipment.stabilityBall => equipmentStabilityBall,
    Equipment.abWheel => equipmentAbWheel,
    Equipment.landmine => equipmentLandmine,
    Equipment.sled => equipmentSled,
    Equipment.jumpRope => equipmentJumpRope,
    Equipment.bodyweight => equipmentBodyweight,
    Equipment.other => equipmentOther,
  };

  String levelName(Level level) => switch (level) {
    Level.beginner => levelBeginner,
    Level.intermediate => levelIntermediate,
    Level.advanced => levelAdvanced,
  };

  String mechanicName(Mechanic mechanic) => switch (mechanic) {
    Mechanic.compound => mechanicCompound,
    Mechanic.isolation => mechanicIsolation,
  };

  String movementPatternName(MovementPattern pattern) => switch (pattern) {
    MovementPattern.squat => patternSquat,
    MovementPattern.hinge => patternHinge,
    MovementPattern.lunge => patternLunge,
    MovementPattern.horizontalPush => patternHorizontalPush,
    MovementPattern.verticalPush => patternVerticalPush,
    MovementPattern.horizontalPull => patternHorizontalPull,
    MovementPattern.verticalPull => patternVerticalPull,
    MovementPattern.carry => patternCarry,
    MovementPattern.coreFlexion => patternCoreFlexion,
    MovementPattern.coreStability => patternCoreStability,
    MovementPattern.rotation => patternRotation,
    MovementPattern.explosive => patternExplosive,
    MovementPattern.isolation => patternIsolation,
    MovementPattern.mobility => patternMobility,
  };

  String lateralityName(Laterality laterality) => switch (laterality) {
    Laterality.bilateral => lateralityBilateral,
    Laterality.unilateral => lateralityUnilateral,
    Laterality.alternating => lateralityAlternating,
  };

  String loggingTypeName(LoggingType type) => switch (type) {
    LoggingType.reps => loggingReps,
    LoggingType.weightReps => loggingWeightReps,
    LoggingType.weightedBodyweight => loggingWeightedBodyweight,
    LoggingType.assistedBodyweight => loggingAssistedBodyweight,
    LoggingType.duration => loggingDuration,
    LoggingType.weightDuration => loggingWeightDuration,
  };

  String muscleNames(Iterable<Muscle> muscles) =>
      inlineList(muscles.map(muscleName));

  String equipmentNames(Iterable<Equipment> equipment) =>
      inlineList(equipment.map(equipmentName));

  /// [items] written inline, separated as the language does.
  String inlineList(Iterable<String> items) => items.join(listSeparator);
}

extension LocalizedExercise on Exercise {
  /// The text in the app's current language, or English when it has none.
  ExerciseText localized(BuildContext context) =>
      text(Localizations.localeOf(context).languageCode);
}
