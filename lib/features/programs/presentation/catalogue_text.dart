import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../profile/presentation/profile_questions.dart';
import '../domain/catalogue_program.dart';
import '../domain/catalogue_queries.dart';
import '../domain/program_editing.dart';

extension CatalogueTextLabels on AppLocalizations {
  /// "Beginner · Build muscle · 3 days a week · 12 weeks".
  String catalogueFacts(CatalogueProgram program) => [
    levelName(program.level),
    goalName(program.goal),
    catalogueDaysPerWeek(program.daysPerWeek),
    if (program.lengthWeeks case final weeks?) programWeekCount(weeks),
  ].join(' · ');

  /// "3 days · Intermediate · 8 weeks".
  String catalogueRowFacts(CatalogueProgram program) => [
    programDayCount(program.daysPerWeek),
    levelName(program.level),
    if (program.lengthWeeks case final weeks?) programWeekCount(weeks),
  ].join(' · ');

  /// Why the post-onboarding suggestion: the user's answers in a sentence
  /// ("You want to build muscle, train 3 days and use a full gym."), then
  /// the program's own [summary]. Without a goal or days only the summary.
  String suggestionReason(TrainingProfile profile, String summary) {
    final goal = profile.goal;
    final days = profile.daysPerWeek;
    if (goal == null || days == null) return summary;
    final wants = switch (goal) {
      Goal.buildMuscle => suggestionWantsBuildMuscle,
      Goal.getStronger => suggestionWantsGetStronger,
      Goal.loseFat => suggestionWantsLoseFat,
      Goal.generalFitness => suggestionWantsGeneralFitness,
    };
    final owned = profile.equipment;
    final preset = owned == null ? null : EquipmentProfile.matching(owned);
    final answers = preset == null
        ? suggestionAnswersNoEquipment(wants, days)
        : suggestionAnswers(wants, days, switch (preset) {
            EquipmentProfile.fullGym => suggestionUsesFullGym,
            EquipmentProfile.homeGym => suggestionUsesHomeGym,
            EquipmentProfile.dumbbells => suggestionUsesDumbbells,
            EquipmentProfile.bodyweight => suggestionUsesBodyweight,
            EquipmentProfile.bands => suggestionUsesBands,
          });
    final rest = summary.trim();
    return rest.isEmpty ? answers : '$answers $rest';
  }

  /// Level, goal, days a week, length, equipment and session time, each a
  /// tag of its card.
  List<String> catalogueTags(CatalogueProgram program) => [
    levelName(program.level),
    goalName(program.goal),
    catalogueDaysPerWeek(program.daysPerWeek),
    if (program.lengthWeeks case final weeks?) programWeekCount(weeks),
    presetName(program.equipmentProfile),
    if (program.minutes case final minutes?) sessionMinutesText(minutes),
  ];

  /// "Matches your goal and level", "Matches your goal, level and days per
  /// week".
  String matchText(List<MatchReason> reasons) {
    final names = [
      for (final reason in reasons)
        switch (reason) {
          MatchReason.goal => catalogueReasonGoal,
          MatchReason.level => catalogueReasonLevel,
          MatchReason.days => catalogueReasonDays,
          MatchReason.equipment => catalogueReasonEquipment,
        },
    ];
    return catalogueMatches(
      names.length < 2
          ? names.join()
          : catalogueReasonsAnd(
              inlineList(names.take(names.length - 1)),
              names.last,
            ),
    );
  }

  String sessionMinutesText(SessionMinutes minutes) =>
      minutes.min == minutes.max
      ? catalogueMinutes(minutes.min)
      : catalogueMinutesRange(minutes.min, minutes.max);
}
