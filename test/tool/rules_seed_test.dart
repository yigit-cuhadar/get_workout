import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/content_import.dart';
import '../../tool/src/rules_seed.dart';

const _db = 'projects/demo/databases/(default)';

void main() {
  final file = File('content/generator/rules.json');
  final rules = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  const options = <String, Object?>{
    'splits': <Object?>[],
    'sessionMinutes': [30, 60],
    'maxFocusAreas': 2,
  };

  Future<RulesVerdict> valid(String path) async =>
      (problems: const <String>[], options: options);

  group('loadRulesSeed', () {
    test('gives the seed of valid rules with their options', () async {
      String? validated;
      final loaded = await loadRulesSeed(file, (path) {
        validated = path;
        return valid(path);
      });
      expect(validated, file.path);
      expect(loaded.problems, isEmpty);
      expect(loaded.seed?.rules, rules);
      expect(loaded.seed?.options, options);
    });

    test('refuses rules with problems, naming the file', () async {
      final loaded = await loadRulesSeed(
        file,
        (_) async => (problems: ['time: must be an object'], options: null),
      );
      expect(loaded.seed, isNull);
      expect(loaded.problems, [
        'generator/rules.json: time: must be an object',
      ]);
    });

    test('refuses a file that is not JSON without running Node', () async {
      final dir = Directory.systemTemp.createTempSync('rules_seed');
      addTearDown(() => dir.deleteSync(recursive: true));
      final broken = File('${dir.path}/rules.json')..writeAsStringSync('{');
      var ran = false;
      final loaded = await loadRulesSeed(broken, (path) {
        ran = true;
        return valid(path);
      });
      expect(ran, isFalse);
      expect(loaded.seed, isNull);
      expect(loaded.problems.single, startsWith('generator/rules.json: '));
    });
  });

  group('checkRulesSeed', () {
    test('runs no validator when rules exist', () async {
      var ran = false;
      final check = await checkRulesSeed(
        file,
        rulesExist: () async => true,
        validate: (path) {
          ran = true;
          return valid(path);
        },
      );
      expect(ran, isFalse);
      expect(check.exist, isTrue);
      expect(check.seed, isNull);
      expect(check.problems, isEmpty);
    });

    test('gives the seed when no rules exist', () async {
      final check = await checkRulesSeed(
        file,
        rulesExist: () async => false,
        validate: valid,
      );
      expect(check.exist, isFalse);
      expect(check.seed?.rules, rules);
    });

    test('refuses rules with problems when no rules exist', () async {
      final check = await checkRulesSeed(
        file,
        rulesExist: () async => false,
        validate: (_) async => (problems: ['splits: bad'], options: null),
      );
      expect(check.seed, isNull);
      expect(check.problems, ['generator/rules.json: splits: bad']);
    });

    test('lets a validator failure through', () {
      expect(
        checkRulesSeed(
          file,
          rulesExist: () async => false,
          validate: (_) async => throw RulesValidatorException('no node'),
        ),
        throwsA(isA<RulesValidatorException>()),
      );
    });
  });

  group('parseRulesVerdict', () {
    test('reads problems and options', () {
      final verdict = parseRulesVerdict(
        jsonEncode({'problems': <String>[], 'options': options}),
      );
      expect(verdict.problems, isEmpty);
      expect(verdict.options, options);
      expect(
        parseRulesVerdict('{"problems": ["a: b"], "options": null}').problems,
        ['a: b'],
      );
    });

    test('refuses unexpected output clearly', () {
      for (final output in [
        'Segmentation fault',
        '[]',
        '{"options": {}}',
        '{"problems": "a", "options": {}}',
        '{"problems": [1], "options": {}}',
        '{"problems": [], "options": []}',
        '{"problems": []}',
      ]) {
        expect(
          () => parseRulesVerdict(output),
          throwsA(
            isA<RulesValidatorException>().having(
              (e) => e.message,
              'message',
              contains('unexpected output'),
            ),
          ),
          reason: output,
        );
      }
    });
  });

  group('seedRules', () {
    late List<List<Map<String, Object?>>> commits;
    final seed = RulesSeed(rules, options);

    Future<String> run({bool dryRun = false}) => seedRules(
      seed,
      databasePath: _db,
      commit: (writes) async => commits.add(writes),
      dryRun: dryRun,
    );

    setUp(() => commits = []);

    test('writes version 1 in one commit when no rules exist', () async {
      expect(await run(), startsWith('Wrote'));
      expect(commits, hasLength(1));
      final writes = commits.single;
      expect(
        [for (final w in writes) (w['update']! as Map)['name']],
        [
          '$_db/documents/generator/rules',
          '$_db/documents/generator/rules/versions/1',
          '$_db/documents/generator/options',
        ],
      );
      for (final write in writes) {
        expect(write['currentDocument'], {'exists': false});
      }
      final stored = decodeFields(
        (writes[0]['update']! as Map)['fields']! as Map<String, Object?>,
      );
      expect(stored, {
        'version': 1,
        'publishedBy': 'import',
        'publishedByEmail': null,
        'note': 'Seed',
        'rules': rules,
      });
      expect(writes[1]['update'], {
        ...(writes[0]['update']! as Map),
        'name': '$_db/documents/generator/rules/versions/1',
      });
      for (final write in writes.take(2)) {
        expect(write['updateTransforms'], [
          {'fieldPath': 'publishedAt', 'setToServerValue': 'REQUEST_TIME'},
        ]);
      }
      expect(writes[2].containsKey('updateTransforms'), isFalse);
      expect(
        decodeFields(
          (writes[2]['update']! as Map)['fields']! as Map<String, Object?>,
        ),
        {'version': 1, ...options},
      );
    });

    test('a dry run writes nothing', () async {
      expect(await run(dryRun: true), startsWith('Would write'));
      expect(commits, isEmpty);
    });
  });
}
