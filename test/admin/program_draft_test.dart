import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/admin/exercises/domain/exercise_draft.dart';
import 'package:get_workout/admin/programs/domain/program_admin_usecases.dart';
import 'package:get_workout/admin/programs/domain/program_draft.dart';
import 'package:get_workout/features/exercises/domain/content_rules.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/catalogue_rules.dart';
import 'package:get_workout/features/programs/domain/program.dart';

import 'fixtures.dart';
import 'program_fixtures.dart';

void main() {
  group('ProgramDraft', () {
    test('reads and writes the content-file shape', () {
      final json = programJson();
      final draft = ProgramDraft.fromJson(json);
      expect(draft.level, Level.beginner);
      expect(draft.goal, Goal.buildMuscle);
      expect(draft.equipmentProfile, EquipmentProfile.dumbbells);
      expect(draft.textOf('en').name, 'Dumbbell Basics');
      expect(draft.days[1].items.first.group, 'A');
      expect(draft.content(exercises), json);
    });

    test('computes daysPerWeek, equipment and minutes from the days', () {
      final content = programJson();
      expect(content['daysPerWeek'], 2);
      expect(content['equipment'], ['dumbbell', 'bench']);
      expect(content['minutes'], {'min': isA<int>(), 'max': isA<int>()});
      expect(programProblems(content, exercises), isEmpty);
    });

    test('writes unset fields as null and leaves out an unset length', () {
      final content = const ProgramDraft().content(exercises);
      expect(content['level'], isNull);
      expect(content['order'], isNull);
      expect(content, isNot(contains('lengthWeeks')));
      expect(content, isNot(contains('minutes')));
      expect(content['l10n'], {
        'en': {'name': '', 'summary': ''},
      });
    });

    test('reads unknown codes and wrong types as unset', () {
      final draft = ProgramDraft.fromJson({
        ...programJson(),
        'level': 'expert',
        'order': '1',
        'premium': 'yes',
      });
      expect(draft.level, isNull);
      expect(draft.order, isNull);
      expect(draft.premium, isFalse);
    });

    test('an unset number of an item is reported by the rules', () {
      final draft = ProgramDraft.fromJson(programJson());
      final days = [...draft.days];
      days[0] = days[0].copyWith(
        items: [days[0].items[0].copyWith(sets: -1), days[0].items[1]],
      );
      final problems = programProblems(
        draft.copyWith(days: days).content(exercises),
        exercises,
      );
      expect(problems.map((p) => p.field), contains('days[0].items[0].sets'));
    });
  });

  test('a new item has the default targets and the exercise rest', () {
    final item = newProgramItem(
      ExerciseDraft.fromJson(validJson()).copyWith(defaultRestS: 120),
    );
    expect(
      item,
      const ProgramItem(
        exerciseId: 'ex_dumbbell_press',
        sets: 3,
        repMin: 8,
        repMax: 12,
        restS: 120,
      ),
    );
  });

  group('validateCatalogueProgram', () {
    final other = programRecord(
      cardOf(programJson(id: 'pr_other', name: 'Other', order: 2)),
    );

    List<ContentProblem> validate(
      Map<String, Object?> json, {
      bool isNew = false,
      List<ProgramRecord>? catalogue,
    }) => validateCatalogueProgram(
      ProgramDraft.fromJson(json),
      exercises: exercises,
      catalogue: catalogue ?? [other],
      isNew: isNew,
    );

    test('passes a valid program', () {
      expect(validate(programJson()), isEmpty);
    });

    test('reports the rules of one program by field', () {
      final json = programJson()
        ..remove('level')
        ..['days'] = [
          {
            'name': 'Day A',
            'items': [
              {
                'exerciseId': 'ex_old_press',
                'sets': 3,
                'repMin': 8,
                'repMax': 12,
                'restS': 90,
              },
            ],
          },
        ];
      final fields = validate(json).map((p) => p.field);
      expect(fields, contains('level'));
      expect(fields, contains('days[0].items[0].exerciseId'));
    });

    test('a new program cannot take a used id', () {
      final problems = validate(
        programJson(id: 'pr_other', order: 3),
        isNew: true,
      );
      expect(problems, [
        const ContentProblem('id', 'id "pr_other" is already used'),
      ]);
    });

    test('names and orders are unique across the catalogue', () {
      final problems = validate(programJson(name: 'other', order: 2));
      expect(problems.map((p) => p.field), ['catalogue', 'catalogue']);
      expect(problems.map((p) => p.message), [
        'name "other" also used by pr_other',
        'order "2" also used by pr_other',
      ]);
    });

    test('an edit is not compared with the stored version of itself', () {
      final stored = programRecord(cardOf(programJson()));
      expect(validate(programJson(), catalogue: [stored, other]), isEmpty);
    });

    test('the free and premium split never blocks a save', () {
      // One live free program of the six needed.
      expect(validate(programJson(), catalogue: const []), isEmpty);
    });
  });

  test('programWarnings are those of the program once live', () {
    final warnings = programWarnings(
      ProgramDraft.fromJson(programJson(status: 'draft')),
      exercises,
    );
    expect(warnings, contains(startsWith('quads gets 0 weekly sets')));
    expect(warnings, everyElement(isNot(startsWith('pr_'))));
  });

  test('CatalogueHealth reports the catalogue-wide rules of the cards', () {
    final health = CatalogueHealth.of([
      programRecord(cardOf(programJson())),
      programRecord(cardOf(programJson(id: 'pr_b', name: 'B', order: 1))),
    ]);
    expect(health.isHealthy, isFalse);
    expect(health.errors, [
      'pr_b: order "1" also used by pr_dumbbell_basics',
      'live programs: 2 free and 0 premium, needs $freePrograms and '
          '$premiumPrograms',
    ]);
  });
}
