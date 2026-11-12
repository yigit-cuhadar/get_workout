import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';

/// How a generated week is split into days.
enum Split {
  fullBody,
  upperLower,
  pushPullLegs;

  /// The fewest days a week the split can be trained on.
  int get minDays => this == pushPullLegs ? 3 : GeneratorLimits.minDays;
}

/// What one generated day trains.
enum DayKind { fullBody, upper, lower, push, pull, legs }

/// A part of the body to go easy on: none of its muscles is trained
/// directly, and exercises loading them at all are avoided where another
/// one does the job.
enum EasyArea {
  shoulders({Muscle.frontDelt, Muscle.midDelt, Muscle.rearDelt}),
  elbows({Muscle.biceps, Muscle.triceps, Muscle.forearm}),
  lowerBack({Muscle.erector}),
  hips({Muscle.hipFlexor, Muscle.abductor, Muscle.adductor}),
  knees({Muscle.quads});

  const EasyArea(this.muscles);

  final Set<Muscle> muscles;
}

abstract final class GeneratorLimits {
  /// The days per week onboarding offers.
  static const minDays = 2;
  static const maxDays = 6;
  static const sessionMinutes = [30, 45, 60, 75, 90];
  static const maxFocusMuscles = 3;
}

/// The answers the generator works from. [equipment] never holds
/// [Equipment.bodyweight], which everyone has; empty means bodyweight only.
class GeneratorAnswers extends Equatable {
  const GeneratorAnswers({
    required this.goal,
    required this.level,
    required this.daysPerWeek,
    required this.sessionMinutes,
    required this.equipment,
    this.focus = const {},
    this.excluded = const {},
    this.easyArea,
    this.split,
  });

  final Goal goal;
  final Level level;
  final int daysPerWeek;

  /// The longest a session may take by the app's estimate.
  final int sessionMinutes;
  final Set<Equipment> equipment;

  /// Muscles to give more sets.
  final Set<Muscle> focus;

  /// Exercise ids never to use.
  final Set<String> excluded;
  final EasyArea? easyArea;

  /// Null picks the split that suits [daysPerWeek] and [level].
  final Split? split;

  @override
  List<Object?> get props => [
    goal,
    level,
    daysPerWeek,
    sessionMinutes,
    equipment,
    focus,
    excluded,
    easyArea,
    split,
  ];
}
