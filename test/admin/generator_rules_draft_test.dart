import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/admin/generator/domain/generator_rules.dart';
import 'package:get_workout/admin/generator/domain/rules_changes.dart';

import 'generator_fixtures.dart';

void main() {
  final seed = seedRules();
  final ul4 = seedTemplate('upper_lower_4');

  group('GeneratorRules', () {
    test('paths read and print as the server writes them', () {
      const text = 'templates[4].dayList[1].slots[2].pick';
      expect(parsePath(text), [
        'templates',
        4,
        'dayList',
        1,
        'slots',
        2,
        'pick',
      ]);
      expect(pathText(parsePath(text)), text);
      expect(seed.at(['dosing', 'build_muscle', 'primary', 'restS']), 150);
      expect(seed.at(['templates', 99, 'id']), isNull);
    });

    test('set copies on the way and leaves the original alone', () {
      final path = ['dosing', 'build_muscle', 'primary', 'restS'];
      final edited = seed.set(path, 165);
      expect(edited.at(path), 165);
      expect(seed.at(path), 150);
      expect(identical(edited.json['volume'], seed.json['volume']), isTrue);
      expect(edited == seed, isFalse);
      expect(edited.set(path, 150), seed);
      expect(edited.set(path, 150).hashCode, seed.hashCode);
    });

    test('null removes a field and keeps unknown ones', () {
      final withExtra = seed.set(['selection', 'note'], 'kept');
      final edited = withExtra.set(['grouping', 1, 'sessionMax'], null);
      expect(edited.has(['grouping', 1, 'sessionMax']), isFalse);
      expect(edited.at(['selection', 'note']), 'kept');
    });

    test('a new template has an unused id and three days', () {
      final template = newTemplate(seed, split: 'full_body');
      expect(template['id'], 'new_template');
      expect(template['dayList'], hasLength(3));
      final twice = seed.add(['templates'], template);
      expect(newTemplate(twice, split: 'full_body')['id'], 'new_template_2');
    });
  });

  group('rulesChanges', () {
    test('a value edit is one readable line', () {
      final draft = seed.set([
        'dosing',
        'build_muscle',
        'primary',
        'restS',
      ], 165);
      expect(rulesChanges(seed, draft), [
        const RulesChange(
          path: ['dosing', 'build_muscle', 'primary', 'restS'],
          where: 'Dosing · Build muscle · Primary · rest',
          now: '150 s',
          after: '165 s',
        ),
      ]);
      expect(rulesChanges(seed, draft).single.tab, RulesTab.dosing);
    });

    test('ranges, absent targets and lists read as values', () {
      final draft = seed
          .set(['dosing', 'lose_fat', 'core', 'sets', 'advanced', 1], 5)
          .set(['volume', 'targets', 'beginner', 'trap'], 2)
          .set(['time', 'sessionMinutes'], [30, 45, 60])
          .set(['focus', 'areas', 'arms'], ['biceps']);
      expect(
        [
          for (final change in rulesChanges(seed, draft))
            (change.where, change.now, change.after),
        ],
        [
          ('Dosing · Lose fat · Core · sets · Advanced', '3–3', '3–5'),
          ('Volume · Beginner · Trap', '0', '2'),
          ('Areas · focus · Arms', 'Biceps, Triceps', 'Biceps'),
          (
            'Areas · time · session lengths',
            '30, 45, 60, 75, 90 min',
            '30, 45, 60 min',
          ),
        ],
      );
    });

    test('a grouping rule added or edited', () {
      final draft = seed
          .set(['grouping', 0, 'size'], 4)
          .set(['grouping', 0, 'goals'], null)
          .add(
            ['grouping'],
            {
              'roles': ['core'],
              'size': 2,
              'restS': 30,
            },
          );
      expect(
        [for (final c in rulesChanges(seed, draft)) (c.where, c.now, c.after)],
        [
          ('Dosing · grouping · rule 1 · goals', 'Lose fat', 'every goal'),
          ('Dosing · grouping · rule 1 · size', '3', '4'),
          ('Dosing · grouping · rule 3 added', '—', 'added'),
        ],
      );
    });

    test('templates are matched by id: added, removed, a field changed', () {
      final added = newTemplate(seed, split: 'full_body');
      final draft = seed
          .set(['templates', ul4, 'priority'], 12)
          .removeAt(['templates'], seedTemplate('body_part_5'))
          .add(['templates'], added);
      expect(
        [for (final c in rulesChanges(seed, draft)) (c.where, c.now, c.after)],
        [
          ('Template upper_lower_4 · priority', '10', '12'),
          ('Template new_template added', '—', 'added'),
          ('Template body_part_5 removed', 'there', '—'),
        ],
      );
      expect(rulesChanges(seed, draft).map((c) => c.tab).toSet(), {
        RulesTab.templates,
      });
    });

    test('a moved slot changes both places; a day name and extras', () {
      final slots = ['templates', ul4, 'dayList', 0, 'slots'];
      final draft = seed
          .move(slots, 0, 1)
          .set([
            'templates',
            ul4,
            'dayList',
            0,
            'l10n',
            'en',
            'name',
          ], 'Upper 1')
          .set(['templates', ul4, 'dayList', 1, 'extras'], ['quads']);
      final lines = [
        for (final c in rulesChanges(seed, draft)) (c.where, c.now, c.after),
      ];
      expect(lines, [
        ('Template upper_lower_4 · Upper 1 · name', 'Upper A', 'Upper 1'),
        (
          'Template upper_lower_4 · Upper 1 · slot 1 changed',
          slotSummary(seed.at([...slots, 0])),
          slotSummary(seed.at([...slots, 1])),
        ),
        (
          'Template upper_lower_4 · Upper 1 · slot 2 changed',
          slotSummary(seed.at([...slots, 1])),
          slotSummary(seed.at([...slots, 0])),
        ),
        (
          'Template upper_lower_4 · Lower A · extra focus muscles',
          lines[3].$2,
          'Quads',
        ),
      ]);
    });

    test('a slot removed and a day added', () {
      final template = ['templates', ul4];
      final draft = seed
          .removeAt([...template, 'dayList', 1, 'slots'], 0)
          .set([...template, 'days'], 5)
          .add([...template, 'dayList'], newDay(4));
      final count =
          (seed.at([...template, 'dayList', 1, 'slots'])! as List).length;
      final lines = [for (final c in rulesChanges(seed, draft)) c.where];
      // The slots after the removed one each moved up a place.
      expect(lines, [
        'Template upper_lower_4 · days a week',
        for (var s = 1; s < count; s++)
          'Template upper_lower_4 · Lower A · slot $s changed',
        'Template upper_lower_4 · Lower A · slot $count removed',
        'Template upper_lower_4 · Day 5 added',
      ]);
    });

    test('splits by id', () {
      final draft = seed
          .set(['splits', 0, 'l10n', 'en', 'name'], 'Whole body')
          .add(
            ['splits'],
            {
              'id': 'arms',
              'l10n': {
                'en': {'name': 'Arms', 'info': 'Arms only.'},
              },
            },
          );
      expect(
        [for (final c in rulesChanges(seed, draft)) (c.where, c.now, c.after)],
        [
          ('Split full_body · name', 'Full body', 'Whole body'),
          ('Split arms added', '—', 'added'),
        ],
      );
    });

    test('no changes, no lines', () {
      expect(rulesChanges(seed, seedRules()), isEmpty);
    });
  });

  group('problems', () {
    test('parse into a path and a message, with a tab and a place', () {
      final problem = RulesProblem.parse(
        'templates[$ul4].dayList[1].slots[2].pick: needs patterns or muscles',
      );
      expect(problem.message, 'needs patterns or muscles');
      expect(problem.tab, RulesTab.templates);
      expect(
        placeOf(seed, problem.path),
        'Template upper_lower_4 · Lower A · slot 3 · picks',
      );
      expect(
        placeOf(
          seed,
          RulesProblem.parse('dosing.build_muscle.primary.sets.beginner[0]: x')
              .path,
        ),
        'Dosing · Build muscle · Primary · sets · Beginner · min',
      );
      expect(RulesProblem.parse('rules.extra: unknown field').tab, isNull);
    });

    test('concern a field by prefix, or exactly', () {
      final problem = RulesProblem.parse('volume.cap.beginner: too big');
      expect(problem.concerns(['volume', 'cap']), isTrue);
      expect(problem.concerns(['volume', 'cap'], exact: true), isFalse);
      expect(problem.concerns(['volume', 'cap', 'beginner']), isTrue);
      expect(problem.concerns(['volume', 'targets']), isFalse);
    });
  });
}
