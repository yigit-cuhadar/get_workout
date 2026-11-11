import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/content_rules.dart';

import '../../admin/fixtures.dart';

/// [validJson] with [change] applied to a deep copy.
Map<String, Object?> changed(void Function(Map<String, Object?> json) change) {
  final json = validJson();
  json['l10n'] = {
    'en': Map<String, Object?>.of(
      (json['l10n']! as Map<String, Object?>)['en']! as Map<String, Object?>,
    ),
  };
  change(json);
  return json;
}

Map<String, Object?> text(Map<String, Object?> json) =>
    (json['l10n']! as Map<String, Object?>)['en']! as Map<String, Object?>;

void main() {
  test('a valid exercise has no problems', () {
    expect(exerciseProblems(validJson()), isEmpty);
  });

  // Each rule of a single exercise: the change that breaks it, and the one
  // problem it reports.
  final cases = <String, (void Function(Map<String, Object?>), ContentProblem)>{
    'unknown field': (
      (j) => j['color'] = 'red',
      const ContentProblem('color', 'unknown field "color"'),
    ),
    'id format': (
      (j) => j['id'] = 'ex_Bad',
      ContentProblem('id', 'id must match ${idPattern.pattern}'),
    ),
    'id prefix': (
      (j) => j['id'] = 'dumbbell_press',
      ContentProblem('id', 'id must match ${idPattern.pattern}'),
    ),
    'status code': (
      (j) => j['status'] = 'deleted',
      const ContentProblem(
        'status',
        'status "deleted" is not one of draft, live, retired',
      ),
    ),
    'missing required code': (
      (j) => j['mechanic'] = null,
      const ContentProblem(
        'mechanic',
        'mechanic "null" is not one of compound, isolation',
      ),
    ),
    'optional code with an unknown value': (
      (j) => j['gripWidth'] = 'huge',
      const ContentProblem(
        'gripWidth',
        'gripWidth "huge" is not one of narrow, shoulder, wide',
      ),
    ),
    'equipment empty': (
      (j) => j['equipment'] = <String>[],
      const ContentProblem(
        'equipment',
        'equipment must have 1-25 items, has 0',
      ),
    ),
    'equipment unknown code': (
      (j) => j['equipment'] = ['laser'],
      const ContentProblem('equipment', 'equipment has unknown code "laser"'),
    ),
    'equipment duplicates': (
      (j) => j['equipment'] = ['dumbbell', 'dumbbell'],
      const ContentProblem('equipment', 'equipment has duplicates'),
    ),
    'more than three alternative sets': (
      (j) => j['equipmentAlternatives'] = [
        ['kettlebell'],
        ['cable'],
        ['resistance_band'],
        ['machine'],
      ],
      const ContentProblem(
        'equipmentAlternatives',
        'equipmentAlternatives has 4 sets, max 3',
      ),
    ),
    'empty alternative set': (
      (j) => j['equipmentAlternatives'] = [<String>[]],
      const ContentProblem(
        'equipmentAlternatives',
        'equipmentAlternatives sets must be non-empty lists',
      ),
    ),
    'alternative equal to equipment': (
      (j) => j['equipmentAlternatives'] = [
        ['bench', 'dumbbell'],
      ],
      const ContentProblem(
        'equipmentAlternatives',
        'equipment set {bench, dumbbell} is listed twice',
      ),
    ),
    'bodyweight with other equipment': (
      (j) => j['equipment'] = ['bodyweight', 'bench'],
      const ContentProblem(
        'equipment',
        'bodyweight must be listed alone: bodyweight, bench',
      ),
    ),
    'bodyweight with other equipment in an alternative': (
      (j) => j['equipmentAlternatives'] = [
        ['bodyweight', 'box'],
      ],
      const ContentProblem(
        'equipmentAlternatives',
        'bodyweight must be listed alone: bodyweight, box',
      ),
    ),
    'no main muscle': (
      (j) => j['mainMuscles'] = <String>[],
      const ContentProblem(
        'mainMuscles',
        'mainMuscles must have 1-2 items, has 0',
      ),
    ),
    'three main muscles': (
      (j) => j['mainMuscles'] = ['pec', 'lat', 'calf'],
      const ContentProblem(
        'mainMuscles',
        'mainMuscles must have 1-2 items, has 3',
      ),
    ),
    'five secondary muscles': (
      (j) =>
          j['secondaryMuscles'] = ['lat', 'calf', 'glute', 'quads', 'biceps'],
      const ContentProblem(
        'secondaryMuscles',
        'secondaryMuscles must have 0-4 items, has 5',
      ),
    ),
    'muscle both main and secondary': (
      (j) => j['secondaryMuscles'] = ['pec'],
      const ContentProblem(
        'secondaryMuscles',
        'muscles both main and secondary: pec',
      ),
    ),
    'family not snake_case': (
      (j) => j['family'] = 'Dumbbell Press',
      const ContentProblem('family', 'family must be snake_case'),
    ),
    'family rank below 1': (
      (j) => j['familyRank'] = 0,
      const ContentProblem(
        'familyRank',
        'familyRank must be an integer in 1..∞',
      ),
    ),
    'popularity missing': (
      (j) => j.remove('popularity'),
      const ContentProblem(
        'popularity',
        'popularity must be an integer in 1..∞',
      ),
    ),
    'rest too short': (
      (j) => j['defaultRestS'] = 10,
      const ContentProblem(
        'defaultRestS',
        'defaultRestS must be an integer in 15..600',
      ),
    ),
    'rest too long': (
      (j) => j['defaultRestS'] = 601,
      const ContentProblem(
        'defaultRestS',
        'defaultRestS must be an integer in 15..600',
      ),
    ),
    'pinned not a list of ids': (
      (j) => j['pinnedAlternatives'] = [1],
      const ContentProblem(
        'pinnedAlternatives',
        'pinnedAlternatives must be a list of ids',
      ),
    ),
    'increment missing for a weighted type': (
      (j) => j.remove('incrementKg'),
      const ContentProblem(
        'incrementKg',
        'incrementKg must be a positive number for weight_reps',
      ),
    ),
    'increment zero': (
      (j) => j['incrementKg'] = 0,
      const ContentProblem(
        'incrementKg',
        'incrementKg must be a positive number for weight_reps',
      ),
    ),
    'increment for an unweighted type': (
      (j) => j['loggingType'] = 'reps',
      const ContentProblem(
        'incrementKg',
        'incrementKg must be absent for reps',
      ),
    ),
    'another language': (
      (j) => j['l10n'] = {...j['l10n']! as Map<String, Object?>, 'de': {}},
      const ContentProblem('l10n', 'l10n has unexpected language "de"'),
    ),
    'no English text': (
      (j) => j['l10n'] = <String, Object?>{},
      const ContentProblem('l10n', 'l10n.en is missing'),
    ),
    'unknown text field': (
      (j) => text(j)['tips'] = <String>[],
      const ContentProblem('l10n.en.tips', 'l10n.en has unknown field "tips"'),
    ),
    'empty name': (
      (j) => text(j)['name'] = '',
      const ContentProblem(
        'l10n.en.name',
        'l10n.en.name must be a non-empty string',
      ),
    ),
    'name with stray spaces': (
      (j) => text(j)['name'] = 'Dumbbell  Press',
      const ContentProblem(
        'l10n.en.name',
        'l10n.en.name has stray spaces: "Dumbbell  Press"',
      ),
    ),
    'nine aliases': (
      (j) => text(j)['aliases'] = [for (var i = 0; i < 9; i++) 'Alias $i'],
      const ContentProblem(
        'l10n.en.aliases',
        'l10n.en.aliases must have 0-8 items, has 9',
      ),
    ),
    'alias repeats the name': (
      (j) => text(j)['aliases'] = ['dumbbell press'],
      const ContentProblem('l10n.en.aliases', 'an alias repeats the name'),
    ),
    'one setup line': (
      (j) => text(j)['setup'] = ['Lie down.'],
      const ContentProblem(
        'l10n.en.setup',
        'l10n.en.setup must have 2-5 items, has 1',
      ),
    ),
    'six execution lines': (
      (j) => text(j)['execution'] = [for (var i = 0; i < 6; i++) 'Step $i.'],
      const ContentProblem(
        'l10n.en.execution',
        'l10n.en.execution must have 2-5 items, has 6',
      ),
    ),
    'five mistakes': (
      (j) => text(j)['mistakes'] = [for (var i = 0; i < 5; i++) 'Mistake $i.'],
      const ContentProblem(
        'l10n.en.mistakes',
        'l10n.en.mistakes must have 2-4 items, has 5',
      ),
    ),
    'no cues': (
      (j) => text(j)['cues'] = <String>[],
      const ContentProblem(
        'l10n.en.cues',
        'l10n.en.cues must have 1-3 items, has 0',
      ),
    ),
    'duplicate lines': (
      (j) => text(j)['mistakes'] = ['Bouncing.', 'Bouncing.'],
      const ContentProblem(
        'l10n.en.mistakes',
        'l10n.en.mistakes has duplicates',
      ),
    ),
    'empty line': (
      (j) => text(j)['cues'] = [''],
      const ContentProblem(
        'l10n.en.cues',
        'l10n.en.cues item must be a non-empty string',
      ),
    ),
    'safety with stray spaces': (
      (j) => text(j)['safety'] = ' Careful.',
      const ContentProblem(
        'l10n.en.safety',
        'l10n.en.safety has stray spaces: " Careful."',
      ),
    ),
  };

  for (final MapEntry(key: rule, value: (change, problem)) in cases.entries) {
    test('reports: $rule', () {
      expect(exerciseProblems(changed(change)), [problem]);
    });
  }

  test('a bodyweight-only exercise without increment is valid', () {
    final json = changed((j) {
      j['loggingType'] = 'reps';
      j['equipment'] = ['bodyweight'];
      j.remove('incrementKg');
      j.remove('equipmentAlternatives');
    });
    expect(exerciseProblems(json), isEmpty);
  });

  group('checkLibrary', () {
    List<String> errorsOf(List<Map<String, Object?>> library) =>
        checkLibrary([for (final json in library) ExerciseEntry(json)]).errors
            .where((e) => !e.startsWith('coverage:'))
            .toList();

    test('needs live popularity and family ranks 1..N', () {
      expect(
        errorsOf([
          validJson(id: 'ex_a', name: 'A', popularity: 1),
          validJson(id: 'ex_b', name: 'B', popularity: 3, familyRank: 3),
          // Not live: ignored by both rules.
          validJson(id: 'ex_c', name: 'C', popularity: 9, status: 'draft'),
        ]),
        [
          'popularity 2 is unused',
          'family dumbbell_press ranks are not 1..2: ex_a=1, ex_b=3',
        ],
      );
    });

    test('names are unique and references exist', () {
      final pinned = validJson(id: 'ex_b', name: 'a', popularity: 2)
        ..['pinnedAlternatives'] = ['ex_missing'];
      expect(
        errorsOf([validJson(id: 'ex_a', name: 'A'), pinned]),
        contains('ex_b: name "a" also used by ex_a'),
      );
      expect(
        errorsOf([validJson(id: 'ex_a', name: 'A'), pinned]),
        contains('ex_b: pinnedAlternatives has invalid id "ex_missing"'),
      );
    });

    test('reports the coverage minimums', () {
      final check = checkLibrary([ExerciseEntry(validJson())]);
      expect(check.errors, contains('coverage: total has 1, needs 400'));
      expect(check.errors, contains('coverage: pec has 1, needs 12'));
    });
  });
}
