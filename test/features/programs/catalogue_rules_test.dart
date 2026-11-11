import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/content_rules.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/catalogue_rules.dart';
import 'package:get_workout/features/programs/domain/program_validation.dart';

import '../../admin/fixtures.dart';

/// The exercises the programs below use, by id.
final library = {
  for (final json in [
    // dumbbell + bench, or kettlebell + bench; beginner; pec, triceps.
    validJson(),
    {
      ...validJson(id: 'ex_plank', name: 'Plank'),
      'loggingType': 'duration',
      'equipment': ['bodyweight'],
      'equipmentAlternatives': null,
      'mainMuscles': ['abdominal'],
      'secondaryMuscles': ['glute'],
    },
    {
      ...validJson(id: 'ex_cable_row', name: 'Cable Row'),
      'equipment': ['cable'],
      'equipmentAlternatives': null,
      'mainMuscles': ['lat'],
      'secondaryMuscles': ['biceps'],
    },
    {
      ...validJson(id: 'ex_kettlebell_press', name: 'Kettlebell Press'),
      'equipment': ['kettlebell'],
      'equipmentAlternatives': [
        ['dumbbell'],
      ],
    },
    {
      ...validJson(id: 'ex_advanced_press', name: 'Advanced Press'),
      'level': 'advanced',
    },
    validJson(id: 'ex_retired_press', name: 'Retired Press', status: 'retired'),
  ])
    json['id']! as String: ExerciseEntry(json),
};

Map<String, Object?> item(
  String exerciseId, {
  int sets = 3,
  int? repMin = 8,
  int? repMax = 12,
  int? durationS,
  int restS = 60,
  String? group,
}) => {
  'exerciseId': exerciseId,
  'sets': sets,
  'repMin': ?repMin,
  'repMax': ?repMax,
  'durationS': ?durationS,
  'restS': restS,
  'group': ?group,
};

/// A valid program: one day of a dumbbell press superset with a plank.
Map<String, Object?> validProgram({
  String id = 'pr_test',
  String name = 'Test Program',
  bool premium = false,
  int order = 1,
  String status = 'live',
}) => {
  'id': id,
  'status': status,
  'premium': premium,
  'order': order,
  'level': 'beginner',
  'goal': 'build_muscle',
  'equipmentProfile': 'dumbbells',
  'daysPerWeek': 1,
  'lengthWeeks': 8,
  'equipment': ['dumbbell', 'bench', 'bodyweight'],
  'minutes': {'min': 6, 'max': 6},
  'l10n': {
    'en': {'name': name, 'summary': 'One short day. It has two exercises.'},
  },
  'days': [
    {
      'name': 'Day 1',
      'items': [
        item('ex_dumbbell_press', restS: 0, group: 'A'),
        item('ex_plank', repMin: null, repMax: null, durationS: 30, group: 'A'),
      ],
    },
  ],
};

/// A deep copy of [validProgram] with [change] applied.
Map<String, Object?> changed(void Function(Map<String, Object?> p) change) {
  final program =
      jsonDecode(jsonEncode(validProgram())) as Map<String, Object?>;
  change(program);
  return program;
}

Map<String, Object?> text(Map<String, Object?> p) =>
    (p['l10n']! as Map<String, Object?>)['en']! as Map<String, Object?>;

Map<String, Object?> day(Map<String, Object?> p, [int i = 0]) =>
    (p['days']! as List<Object?>)[i]! as Map<String, Object?>;

List<Object?> items(Map<String, Object?> p) => day(p)['items']! as List;

Map<String, Object?> firstItem(Map<String, Object?> p) =>
    items(p).first! as Map<String, Object?>;

void main() {
  test('a valid program has no problems', () {
    expect(programProblems(validProgram(), library), isEmpty);
  });

  // Each rule of a single program: the change that breaks it, and the
  // problem it reports.
  final cases = <String, (void Function(Map<String, Object?>), ContentProblem)>{
    'unknown field': (
      (p) => p['color'] = 'red',
      const ContentProblem('color', 'unknown field "color"'),
    ),
    'id format': (
      (p) => p['id'] = 'ex_test',
      ContentProblem('id', 'id must match ${programIdPattern.pattern}'),
    ),
    'status code': (
      (p) => p['status'] = 'deleted',
      const ContentProblem(
        'status',
        'status "deleted" is not one of draft, live, retired',
      ),
    ),
    'level code': (
      (p) => p['level'] = 'expert',
      const ContentProblem(
        'level',
        'level "expert" is not one of beginner, intermediate, advanced',
      ),
    ),
    'goal code': (
      (p) => p['goal'] = 'get_lean',
      const ContentProblem(
        'goal',
        'goal "get_lean" is not one of build_muscle, get_stronger, '
            'lose_fat, general_fitness',
      ),
    ),
    'equipment profile code': (
      (p) => p['equipmentProfile'] = 'garage',
      const ContentProblem(
        'equipmentProfile',
        'equipmentProfile "garage" is not one of full_gym, home_gym, '
            'dumbbells, bodyweight, bands',
      ),
    ),
    'premium flag': (
      (p) => p['premium'] = 'yes',
      const ContentProblem('premium', 'premium must be true or false'),
    ),
    'order': (
      (p) => p['order'] = 0,
      const ContentProblem('order', 'order must be an integer ≥ 1'),
    ),
    'lengthWeeks range': (
      (p) => p['lengthWeeks'] = 53,
      const ContentProblem(
        'lengthWeeks',
        'lengthWeeks must be an integer in 1..52',
      ),
    ),
    'daysPerWeek matches the days': (
      (p) => p['daysPerWeek'] = 2,
      const ContentProblem(
        'daysPerWeek',
        'daysPerWeek is 2 but there are 1 days',
      ),
    ),
    'at most seven days': (
      (p) {
        p['days'] = List.filled(8, day(p));
        p['daysPerWeek'] = 8;
      },
      const ContentProblem('days', 'days must be a list of 1-7'),
    ),
    'no days': (
      (p) => p['days'] = <Object?>[],
      const ContentProblem('days', 'days must be a list of 1-7'),
    ),
    'only English text': (
      (p) => (p['l10n']! as Map)['de'] = text(p),
      const ContentProblem('l10n', 'l10n has unexpected language "de"'),
    ),
    'unknown text field': (
      (p) => text(p)['tagline'] = 'Go.',
      const ContentProblem(
        'l10n.en.tagline',
        'l10n.en has unknown field "tagline"',
      ),
    ),
    'name length': (
      (p) => text(p)['name'] = 'N' * 61,
      const ContentProblem(
        'l10n.en.name',
        'l10n.en.name is longer than 60 characters',
      ),
    ),
    'name spaces': (
      (p) => text(p)['name'] = 'Test  Program',
      const ContentProblem(
        'l10n.en.name',
        'l10n.en.name has stray spaces: "Test  Program"',
      ),
    ),
    'summary of three sentences': (
      (p) => text(p)['summary'] = 'One. Two. Three.',
      const ContentProblem(
        'l10n.en.summary',
        'l10n.en.summary must be 1-2 full sentences',
      ),
    ),
    'summary without an ending': (
      (p) => text(p)['summary'] = 'One short day',
      const ContentProblem(
        'l10n.en.summary',
        'l10n.en.summary must be 1-2 full sentences',
      ),
    ),
    'missing summary': (
      (p) => text(p).remove('summary'),
      const ContentProblem(
        'l10n.en.summary',
        'l10n.en.summary must be a non-empty string',
      ),
    ),
    'unknown day field': (
      (p) => day(p)['note'] = 'x',
      const ContentProblem('days[0].note', 'days[0] has unknown field "note"'),
    ),
    'day name length': (
      (p) => day(p)['name'] = 'D' * 41,
      const ContentProblem(
        'days[0].name',
        'days[0].name is longer than 40 characters',
      ),
    ),
    'day without items': (
      (p) => day(p)['items'] = <Object?>[],
      const ContentProblem(
        'days[0].items',
        'days[0].items must be a list of 1-20',
      ),
    ),
    'day with too many items': (
      (p) => day(p)['items'] = [
        for (var i = 0; i < 21; i++) item('ex_dumbbell_press'),
      ],
      const ContentProblem(
        'days[0].items',
        'days[0].items must be a list of 1-20',
      ),
    ),
    'no target weight in catalogue programs': (
      (p) => firstItem(p)['targetKg'] = 20,
      const ContentProblem(
        'days[0].items[0].targetKg',
        'days[0].items[0] has unknown field "targetKg"',
      ),
    ),
    'sets range': (
      (p) => firstItem(p)['sets'] = 11,
      const ContentProblem(
        'days[0].items[0].sets',
        'days[0].items[0] sets must be an integer in 1..10',
      ),
    ),
    'rest range': (
      (p) => firstItem(p)['restS'] = 601,
      const ContentProblem(
        'days[0].items[0].restS',
        'days[0].items[0] restS must be an integer in 0..600',
      ),
    ),
    'reps range': (
      (p) => firstItem(p)['repMin'] = 0,
      const ContentProblem(
        'days[0].items[0].repMin',
        'days[0].items[0] reps must be integers in 1..100',
      ),
    ),
    'reps needed for a rep-logged exercise': (
      (p) => firstItem(p).remove('repMax'),
      const ContentProblem(
        'days[0].items[0].repMin',
        'days[0].items[0] needs repMin and repMax',
      ),
    ),
    'repMin not above repMax': (
      (p) => firstItem(p)['repMin'] = 15,
      const ContentProblem(
        'days[0].items[0].repMin',
        'days[0].items[0] has repMin above repMax',
      ),
    ),
    'no duration for a rep-logged exercise': (
      (p) => firstItem(p)['durationS'] = 30,
      const ContentProblem(
        'days[0].items[0].exerciseId',
        'days[0].items[0] does not match how ex_dumbbell_press is logged '
            '(weight_reps)',
      ),
    ),
    'duration range': (
      (p) => (items(p)[1]! as Map)['durationS'] = 4,
      const ContentProblem(
        'days[0].items[1].durationS',
        'days[0].items[1] durationS must be an integer in 5..3600',
      ),
    ),
    'no reps for a duration-logged exercise': (
      (p) => (items(p)[1]! as Map)['repMin'] = 5,
      const ContentProblem(
        'days[0].items[1].exerciseId',
        'days[0].items[1] does not match how ex_plank is logged (duration)',
      ),
    ),
    'unknown exercise': (
      (p) => firstItem(p)['exerciseId'] = 'ex_missing',
      const ContentProblem(
        'days[0].items[0].exerciseId',
        'days[0].items[0] uses "ex_missing", which is not a live exercise',
      ),
    ),
    'retired exercise': (
      (p) => firstItem(p)['exerciseId'] = 'ex_retired_press',
      const ContentProblem(
        'days[0].items[0].exerciseId',
        'days[0].items[0] uses "ex_retired_press", which is not a live '
            'exercise',
      ),
    ),
    'exercise outside the equipment profile': (
      (p) => firstItem(p)['exerciseId'] = 'ex_cable_row',
      const ContentProblem(
        'days[0].items[0].exerciseId',
        'ex_cable_row cannot be done with the dumbbells equipment',
      ),
    ),
    'exercise two levels above the program': (
      (p) => firstItem(p)['exerciseId'] = 'ex_advanced_press',
      const ContentProblem(
        'days[0].items[0].exerciseId',
        'ex_advanced_press is advanced, too hard for a beginner program',
      ),
    ),
    'equipment not computed from the exercises': (
      (p) => p['equipment'] = ['dumbbell', 'bench'],
      const ContentProblem(
        'equipment',
        'equipment must be [dumbbell, bench, bodyweight]',
      ),
    ),
    'equipment out of vocabulary order': (
      (p) => p['equipment'] = ['bench', 'dumbbell', 'bodyweight'],
      const ContentProblem(
        'equipment',
        'equipment must be [dumbbell, bench, bodyweight]',
      ),
    ),
    'minutes not the app\'s estimate': (
      (p) => p['minutes'] = {'min': 5, 'max': 6},
      const ContentProblem('minutes', 'minutes must be {"min": 6, "max": 6}'),
    ),
    'minutes missing': (
      (p) => p.remove('minutes'),
      const ContentProblem('minutes', 'minutes must be {"min": 6, "max": 6}'),
    ),
    'group is one capital letter': (
      (p) {
        for (final i in items(p)) {
          (i! as Map)['group'] = 'a';
        }
      },
      const ContentProblem(
        'days[0].items[0].group',
        'days[0].items[0].group must be one letter A-Z',
      ),
    ),
    'group of one item': (
      (p) => (items(p)[1]! as Map).remove('group'),
      const ContentProblem(
        'days[0].items[0].group',
        'days[0].items[0] group A needs two or more adjacent items',
      ),
    ),
    'group split by another item': (
      (p) => items(p).insert(1, item('ex_dumbbell_press')),
      const ContentProblem(
        'days[0].items[0].group',
        'days[0].items[0] group A needs two or more adjacent items',
      ),
    ),
  };

  cases.forEach((rule, testCase) {
    final (change, problem) = testCase;
    test('reports: $rule', () {
      expect(programProblems(changed(change), library), contains(problem));
    });
  });

  test('an exercise one level above the program is allowed', () {
    final program = changed((p) {
      p['level'] = 'intermediate';
      firstItem(p)['exerciseId'] = 'ex_advanced_press';
    });
    expect(programProblems(program, library), isEmpty);
  });

  test('an exercise fits a profile through an alternative set', () {
    final program = changed((p) {
      firstItem(p)['exerciseId'] = 'ex_kettlebell_press';
      // Its primary equipment, not the alternative, makes the list.
      p['equipment'] = ['kettlebell', 'bodyweight'];
    });
    expect(programProblems(program, library), isEmpty);
  });

  test('a valid program is one the app accepts', () {
    final program = ProgramEntry(validProgram()).program;
    expect(program.name, 'Test Program');
    expect(program.days.single.items.first.group, 'A');
    expect(validateProgram(program, liveLoggingTypes(library)).isValid, isTrue);
  });

  test('values of the wrong type become ones the app rejects', () {
    final program = ProgramEntry(
      changed((p) {
        p['lengthWeeks'] = '8';
        firstItem(p)
          ..['sets'] = '3'
          ..['repMin'] = 8.5;
      }),
    ).program;
    final result = validateProgram(program, liveLoggingTypes(library));

    expect(result.program, {ProgramIssue.lengthWeeksOutOfRange});
    expect(result.itemIssues(0, 0), {
      ItemIssue.setsOutOfRange,
      ItemIssue.repsOutOfRange,
    });
  });

  test('liveLoggingTypes leaves out exercises that are not live', () {
    expect(liveLoggingTypes(library).keys, isNot(contains('ex_retired_press')));
    expect(liveLoggingTypes(library)['ex_plank'], LoggingType.duration);
  });

  test('programEquipment is the primary equipment in vocabulary order', () {
    expect(programEquipment(ProgramEntry(validProgram()), library), [
      'dumbbell',
      'bench',
      'bodyweight',
    ]);
  });

  test('summarizeProgram estimates minutes and weekly sets', () {
    final program = changed(
      (p) => p['days'] = [
        day(p),
        {
          'name': 'Day 2',
          'items': [item('ex_cable_row', sets: 4, restS: 120)],
        },
      ],
    );
    final summary = summarizeProgram(ProgramEntry(program), library);

    // The app's estimate. Day 1, a superset: 3 x 30 s of reps and 3 x 30 s
    // of plank, then 3 rounds of 60 s rest = 360 s; day 2: 4 x (30 + 120).
    expect(summary.minutesPerDay, [6, 10]);
    expect(summary.weeklySets, {
      Muscle.pec: 3.0,
      Muscle.triceps: 1.5,
      Muscle.abdominal: 3.0,
      Muscle.glute: 1.5,
      Muscle.lat: 4.0,
      Muscle.biceps: 2.0,
    });
  });

  group('checkCatalogue', () {
    List<ProgramEntry> catalogue({int free = 6, int premium = 19}) => [
      for (var i = 0; i < free + premium; i++)
        ProgramEntry(
          validProgram(
            id: 'pr_p$i',
            name: 'Program $i',
            order: i + 1,
            premium: i >= free,
          ),
        ),
    ];

    test('accepts 6 free and 19 premium live programs', () {
      expect(checkCatalogue(catalogue(), library).errors, isEmpty);
    });

    test('needs exactly 6 free and 19 premium live programs', () {
      expect(checkCatalogue(catalogue(free: 7, premium: 18), library).errors, [
        'live programs: 7 free and 18 premium, needs 6 and 19',
      ]);
    });

    test('counts only live programs', () {
      final programs = [
        ...catalogue(),
        ProgramEntry(
          validProgram(
            id: 'pr_draft',
            name: 'Draft',
            order: 99,
            status: 'draft',
          ),
        ),
      ];
      expect(checkCatalogue(programs, library).errors, isEmpty);
    });

    test('ids, names and orders are unique', () {
      final programs = [
        ...catalogue(),
        ProgramEntry(validProgram(id: 'pr_p0', name: 'PROGRAM 1', order: 3)),
      ];
      expect(checkCatalogue(programs, library).errors, [
        'pr_p0: id "pr_p0" also used by pr_p0',
        'pr_p0: name "program 1" also used by pr_p1',
        'pr_p0: order "3" also used by pr_p2',
        'live programs: 7 free and 19 premium, needs 6 and 19',
      ]);
    });

    test('warns when a major muscle is outside its level band', () {
      final check = checkCatalogue(catalogue(free: 1, premium: 0), library);
      // One day of 3 pec and 1.5 triceps sets; a beginner band is 6-12.
      expect(check.warnings, [
        for (final muscle in majorMuscles)
          'pr_p0: ${muscle.code} gets ${switch (muscle) {
            Muscle.pec => '3',
            Muscle.triceps => '1.5',
            Muscle.glute => '1.5',
            _ => '0',
          }} weekly sets, beginner band is 6-12',
      ]);
    });
  });

  group('EquipmentProfile', () {
    test('a full gym has everything but bodyweight', () {
      expect(
        EquipmentProfile.fullGym.equipment,
        Equipment.values.toSet()..remove(Equipment.bodyweight),
      );
    });

    test('no profile lists bodyweight, which every profile has', () {
      for (final profile in EquipmentProfile.values) {
        expect(profile.equipment, isNot(contains(Equipment.bodyweight)));
        expect(profile.has(['bodyweight']), isTrue);
      }
    });

    test('has checks every code of a set', () {
      expect(EquipmentProfile.dumbbells.has(['dumbbell', 'bench']), isTrue);
      expect(EquipmentProfile.dumbbells.has(['dumbbell', 'box']), isFalse);
      expect(EquipmentProfile.fullGym.has(['sled', 'other']), isTrue);
    });
  });
}
