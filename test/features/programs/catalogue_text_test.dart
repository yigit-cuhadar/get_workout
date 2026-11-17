import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/catalogue_queries.dart';
import 'package:get_workout/features/programs/presentation/catalogue_text.dart';
import 'package:get_workout/l10n/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  const summary = 'Push, pull and legs, each once a week.';

  group('suggestionReason', () {
    const all = MatchReason.values;
    final fullGym = TrainingProfile(
      goal: Goal.buildMuscle,
      level: Level.intermediate,
      daysPerWeek: 3,
      equipment: EquipmentProfile.fullGym.equipment.toSet(),
    );

    test('names the goal, the days and the equipment set it matches', () {
      expect(
        l10n.suggestionReason(fullGym, all, summary),
        'You want to build muscle, train 3 days and use a full gym. '
        '$summary',
      );
    });

    test('leaves out days the program does not match', () {
      expect(
        l10n.suggestionReason(fullGym, const [
          MatchReason.goal,
          MatchReason.level,
          MatchReason.equipment,
        ], summary),
        'You want to build muscle and use a full gym. $summary',
      );
    });

    test('leaves out a goal the program does not match', () {
      expect(
        l10n.suggestionReason(fullGym, const [
          MatchReason.days,
          MatchReason.equipment,
        ], summary),
        'You want to train 3 days and use a full gym. $summary',
      );
    });

    test('leaves out equipment that is no set', () {
      const profile = TrainingProfile(
        goal: Goal.loseFat,
        daysPerWeek: 1,
        equipment: {Equipment.kettlebell},
      );

      expect(
        l10n.suggestionReason(profile, all, summary),
        'You want to lose fat and train 1 day. $summary',
      );
    });

    test('names a single match alone', () {
      expect(
        l10n.suggestionReason(fullGym, const [MatchReason.goal], summary),
        'You want to build muscle. $summary',
      );
    });

    test('is the summary alone when nothing it names matches', () {
      expect(
        l10n.suggestionReason(fullGym, const [MatchReason.level], summary),
        summary,
      );
      expect(
        l10n.suggestionReason(const TrainingProfile(), all, summary),
        summary,
      );
    });
  });
}
