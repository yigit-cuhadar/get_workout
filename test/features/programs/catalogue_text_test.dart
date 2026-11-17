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
    test('names the goal, the days and the equipment set', () {
      final profile = TrainingProfile(
        goal: Goal.buildMuscle,
        daysPerWeek: 3,
        equipment: EquipmentProfile.fullGym.equipment.toSet(),
      );

      expect(
        l10n.suggestionReason(profile, summary),
        'You want to build muscle, train 3 days and use a full gym. '
        '$summary',
      );
    });

    test('leaves out equipment that is no set', () {
      const profile = TrainingProfile(
        goal: Goal.loseFat,
        daysPerWeek: 1,
        equipment: {Equipment.kettlebell},
      );

      expect(
        l10n.suggestionReason(profile, summary),
        'You want to lose fat and train 1 day. $summary',
      );
    });

    test('is the summary alone without a goal or days', () {
      expect(
        l10n.suggestionReason(const TrainingProfile(daysPerWeek: 3), summary),
        summary,
      );
    });
  });
}
