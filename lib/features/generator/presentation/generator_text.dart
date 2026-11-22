import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';

extension GeneratorText on AppLocalizations {
  String focusAreaName(FocusArea area) => switch (area) {
    FocusArea.chest => generatorAreaChest,
    FocusArea.back => generatorAreaBack,
    FocusArea.shoulders => generatorAreaShoulders,
    FocusArea.arms => generatorAreaArms,
    FocusArea.core => generatorAreaCore,
    FocusArea.glutes => generatorAreaGlutes,
    FocusArea.legs => generatorAreaLegs,
  };

  String sensitiveAreaName(SensitiveArea area) => switch (area) {
    SensitiveArea.shoulders => generatorSensitiveShoulders,
    SensitiveArea.elbowsWrists => generatorSensitiveElbowsWrists,
    SensitiveArea.lowerBack => generatorSensitiveLowerBack,
    SensitiveArea.hips => generatorSensitiveHips,
    SensitiveArea.knees => generatorSensitiveKnees,
  };

  String equipmentStyleName(EquipmentStyle style) => switch (style) {
    EquipmentStyle.any => generatorStyleAny,
    EquipmentStyle.machines => generatorStyleMachines,
    EquipmentStyle.freeWeights => generatorStyleFreeWeights,
  };

  String equipmentStyleInfo(EquipmentStyle style) => switch (style) {
    EquipmentStyle.any => generatorStyleAnyInfo,
    EquipmentStyle.machines => generatorStyleMachinesInfo,
    EquipmentStyle.freeWeights => generatorStyleFreeWeightsInfo,
  };
}
