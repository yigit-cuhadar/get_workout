import '../../../l10n/app_localizations.dart';
import '../domain/generator_answers.dart';
import '../domain/program_generator.dart';
import 'generator_questions_cubit.dart';

extension GeneratorText on AppLocalizations {
  String splitName(TrainingSplit split) => switch (split) {
    TrainingSplit.fullBody => generatorSplitFullBody,
    TrainingSplit.upperLower => generatorSplitUpperLower,
    TrainingSplit.pushPullLegs => generatorSplitPushPullLegs,
  };

  String dayKindName(DayKind kind) => switch (kind) {
    DayKind.fullBody => generatorDayFullBody,
    DayKind.upper => generatorDayUpper,
    DayKind.lower => generatorDayLower,
    DayKind.push => generatorDayPush,
    DayKind.pull => generatorDayPull,
    DayKind.legs => generatorDayLegs,
  };

  /// "Upper", or "Upper A" when the week has more than one.
  String generatedDayName(GeneratedDay day) {
    final variant = day.variant;
    return variant == null
        ? dayKindName(day.kind)
        : generatorDayVariant(
            dayKindName(day.kind),
            String.fromCharCode('A'.codeUnitAt(0) + variant),
          );
  }

  String easyAreaName(EasyArea area) => switch (area) {
    EasyArea.shoulders => generatorAreaShoulders,
    EasyArea.elbows => generatorAreaElbows,
    EasyArea.lowerBack => generatorAreaLowerBack,
    EasyArea.hips => generatorAreaHips,
    EasyArea.knees => generatorAreaKnees,
  };

  String generatorQuestion(GeneratorStep step) => switch (step) {
    GeneratorStep.goal => questionGoal,
    GeneratorStep.level => questionLevel,
    GeneratorStep.days => questionDaysPerWeek,
    GeneratorStep.session => generatorQuestionSession,
    GeneratorStep.equipment => questionEquipment,
    GeneratorStep.focus => generatorQuestionFocus,
    GeneratorStep.excluded => generatorQuestionExcluded,
    GeneratorStep.easyArea => generatorQuestionEasyArea,
    GeneratorStep.split => generatorQuestionSplit,
  };

  String? generatorQuestionInfo(GeneratorStep step) => switch (step) {
    GeneratorStep.equipment => questionEquipmentInfo,
    GeneratorStep.focus => generatorFocusInfo(GeneratorLimits.maxFocusMuscles),
    GeneratorStep.excluded => generatorExcludedInfo,
    GeneratorStep.easyArea => generatorEasyAreaInfo,
    _ => null,
  };

  String generationIssueText(GenerationIssue? issue) => switch (issue) {
    GenerationIssue.daysOutOfRange => generatorIssueDays(
      GeneratorLimits.minDays,
      GeneratorLimits.maxDays,
    ),
    GenerationIssue.splitNeedsMoreDays => generatorIssueSplit(
      TrainingSplit.pushPullLegs.minDays,
    ),
    GenerationIssue.noExercises => generatorIssueNoExercises,
    null => generatorFailed,
  };
}
