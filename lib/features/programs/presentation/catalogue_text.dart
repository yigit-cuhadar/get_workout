import '../../../l10n/app_localizations.dart';
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

  String matchText(List<MatchReason> reasons) => catalogueMatches(
    inlineList(
      reasons.map(
        (reason) => switch (reason) {
          MatchReason.goal => catalogueReasonGoal,
          MatchReason.level => catalogueReasonLevel,
          MatchReason.days => catalogueReasonDays,
          MatchReason.equipment => catalogueReasonEquipment,
        },
      ),
    ),
  );

  String sessionMinutesText(SessionMinutes minutes) =>
      minutes.min == minutes.max
      ? catalogueMinutes(minutes.min)
      : catalogueMinutesRange(minutes.min, minutes.max);
}
