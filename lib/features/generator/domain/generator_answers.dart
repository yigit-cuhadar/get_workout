import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';

const _machineKinds = {
  Equipment.machine,
  Equipment.cable,
  Equipment.smithMachine,
};

const _freeWeightKinds = {
  Equipment.barbell,
  Equipment.ezBar,
  Equipment.trapBar,
  Equipment.dumbbell,
  Equipment.kettlebell,
};

/// Whether the equipment style question applies to [equipment]: it has a
/// machine kind and a free-weight kind to choose between.
bool equipmentStyleApplies(Set<Equipment> equipment) =>
    equipment.any(_machineKinds.contains) &&
    equipment.any(_freeWeightKinds.contains);

/// The answers a program is generated from (SPEC.md, `generateProgram`).
class GeneratorAnswers extends Equatable {
  const GeneratorAnswers({
    required this.goal,
    required this.level,
    required this.daysPerWeek,
    required this.sessionMinutes,
    required this.equipment,
    this.focus = const {},
    this.skip = const {},
    this.sensitive = const {},
    this.equipmentStyle = EquipmentStyle.any,
    this.splitId,
  });

  final Goal goal;
  final Level level;
  final int daysPerWeek;
  final int sessionMinutes;

  /// Never holds [Equipment.bodyweight], which everyone has; empty means
  /// bodyweight only.
  final Set<Equipment> equipment;

  /// Areas that get more sets.
  final Set<FocusArea> focus;

  /// Areas the user does not want to train; never one of [focus].
  final Set<FocusArea> skip;
  final Set<SensitiveArea> sensitive;
  final EquipmentStyle equipmentStyle;

  /// A split of the options; null lets the server choose.
  final String? splitId;

  @override
  List<Object?> get props => [
    goal,
    level,
    daysPerWeek,
    sessionMinutes,
    equipment,
    focus,
    skip,
    sensitive,
    equipmentStyle,
    splitId,
  ];
}
