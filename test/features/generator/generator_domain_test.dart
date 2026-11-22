import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/generator/domain/generator_answers.dart';
import 'package:get_workout/features/generator/domain/generator_options.dart';
import 'package:get_workout/features/programs/domain/program.dart';

import 'fixtures.dart';

void main() {
  group('focusAreaMuscles', () {
    test('holds every muscle in exactly one area', () {
      final all = [for (final muscles in focusAreaMuscles.values) ...muscles];
      expect(all, hasLength(Muscle.values.length));
      expect(all.toSet(), Muscle.values.toSet());
      expect(focusAreaMuscles.keys, FocusArea.values);
    });

    test('names the area of a muscle', () {
      expect(focusAreaOf(Muscle.rearDelt), FocusArea.shoulders);
      expect(focusAreaOf(Muscle.erector), FocusArea.back);
      expect(focusAreaOf(Muscle.abductor), FocusArea.legs);
    });
  });

  group('equipmentStyleApplies', () {
    test('needs a machine kind and a free-weight kind', () {
      expect(equipmentStyleApplies(EquipmentProfile.fullGym.equipment), true);
      expect(equipmentStyleApplies({Equipment.cable, Equipment.ezBar}), true);
      expect(
        equipmentStyleApplies({Equipment.smithMachine, Equipment.kettlebell}),
        true,
      );
    });

    test('does not apply with only one of them', () {
      expect(equipmentStyleApplies(EquipmentProfile.homeGym.equipment), false);
      expect(
        equipmentStyleApplies({Equipment.machine, Equipment.cable}),
        false,
      );
      expect(equipmentStyleApplies({Equipment.resistanceBand}), false);
      expect(equipmentStyleApplies(const {}), false);
    });
  });

  group('GeneratorOptions', () {
    test('lists the splits fitting the days, level and goal in order', () {
      List<String> ids(int days, Level level, Goal goal) => [
        for (final split in options.splitsFitting(days, level, goal)) split.id,
      ];
      expect(ids(3, Level.intermediate, Goal.buildMuscle), [
        'full_body',
        'ppl',
      ]);
      // Push/pull/legs for 3 days is only for building muscle, and not for
      // beginners.
      expect(ids(3, Level.intermediate, Goal.loseFat), ['full_body']);
      expect(ids(3, Level.beginner, Goal.buildMuscle), ['full_body']);
      expect(ids(4, Level.beginner, Goal.loseFat), ['upper_lower']);
      expect(ids(5, Level.advanced, Goal.buildMuscle), isEmpty);
    });

    test('picks 60 minutes when offered, else the middle length', () {
      expect(options.defaultSessionMinutes, 60);
      const other = GeneratorOptions(
        splits: [],
        sessionMinutes: [20, 40, 50],
        maxFocusAreas: 2,
        maxSkipAreas: 3,
      );
      expect(other.defaultSessionMinutes, 40);
    });

    test('names a split in the language, else in English', () {
      const split = GeneratorSplit(
        id: 'x',
        l10n: {
          'en': (name: 'Upper/lower', info: 'Upper and lower days'),
          'tr': (name: 'Üst/alt', info: 'Üst ve alt günler'),
        },
        fits: [],
      );
      expect(split.text('tr').name, 'Üst/alt');
      expect(split.text('de').name, 'Upper/lower');
    });
  });

  group('GeneratedProgram', () {
    test('saves as a generated program with the server\'s days', () {
      final program = generated([
        ['a', 'b'],
        ['c'],
      ]).toProgram(name: 'Full body, 2 days');
      expect(program.name, 'Full body, 2 days');
      expect(program.origin, ProgramOrigin.generated);
      expect(program.lengthWeeks, 8);
      expect(program.premium, false);
      expect(program.days.map((day) => day.name), [
        'Full body A',
        'Full body B',
      ]);
      expect(program.days.first.items.map((item) => item.exerciseId), [
        'a',
        'b',
      ]);
    });

    test('names the uncovered muscles no exercise works as a main one', () {
      final program = generated(
        [
          ['squat'],
        ],
        uncovered: {Muscle.calf, Muscle.quads},
      );
      expect(program.stillUncovered(const {}), {Muscle.calf, Muscle.quads});
      expect(
        program.stillUncovered({
          'squat': lift('squat', [Muscle.quads]),
        }),
        {Muscle.calf},
      );
    });
  });
}
