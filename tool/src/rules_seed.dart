// Seeding the program generator's rules (SPEC.md, `generator/rules`) from
// content/generator/rules.json. The validator lives only in the functions,
// so the file is checked by their built CLI through Node.
import 'dart:convert';
import 'dart:io';

import 'content_import.dart';

const rulesCliPath = 'functions/lib/generator/cli.js';

/// What the functions' validator says of a rules file: its problems, and
/// the `generator/options` it gives when it has none.
typedef RulesVerdict = ({List<String> problems, Map<String, Object?>? options});

/// Validates the rules file at a path.
typedef RulesValidator = Future<RulesVerdict> Function(String path);

/// The validator cannot run: not built, or Node failed.
class RulesValidatorException implements Exception {
  RulesValidatorException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// [RulesValidator] through `node functions/lib/generator/cli.js`.
Future<RulesVerdict> validateRulesWithNode(String path) async {
  if (!File(rulesCliPath).existsSync()) {
    throw RulesValidatorException(
      '$rulesCliPath is missing: run `npm run build` in functions/ first.',
    );
  }
  final ProcessResult result;
  try {
    result = await Process.run('node', [rulesCliPath, path]);
  } on ProcessException catch (e) {
    throw RulesValidatorException('Could not run node: ${e.message}');
  }
  if (result.exitCode != 0) {
    throw RulesValidatorException(
      '$rulesCliPath failed (exit ${result.exitCode}): ${result.stderr}',
    );
  }
  final json = jsonDecode(result.stdout as String) as Map<String, Object?>;
  return (
    problems: (json['problems']! as List<Object?>).cast<String>(),
    options: json['options'] as Map<String, Object?>?,
  );
}

/// Valid rules and the options they give, ready to be written as version 1.
class RulesSeed {
  RulesSeed(this.rules, this.options);

  final Map<String, Object?> rules;
  final Map<String, Object?> options;

  /// `generator/rules`, `generator/rules/versions/1` and `generator/options`,
  /// each written only if it does not exist yet.
  List<Map<String, Object?>> writes(String databasePath) {
    final document = {
      'version': 1,
      'publishedBy': 'import',
      'publishedByEmail': null,
      'note': 'Seed',
      'rules': rules,
    };
    Map<String, Object?> create(
      String path,
      Map<String, Object?> fields, {
      bool published = false,
    }) => {
      'update': {
        'name': '$databasePath/documents/$path',
        'fields': encodeFields(fields),
      },
      if (published)
        'updateTransforms': [
          {'fieldPath': 'publishedAt', 'setToServerValue': 'REQUEST_TIME'},
        ],
      'currentDocument': {'exists': false},
    };
    return [
      create('generator/rules', document, published: true),
      create('generator/rules/versions/1', document, published: true),
      create('generator/options', {'version': 1, ...options}),
    ];
  }
}

/// Reads and validates the rules [file]: the seed, or the problems that
/// refuse it.
Future<({RulesSeed? seed, List<String> problems})> loadRulesSeed(
  File file,
  RulesValidator validate,
) async {
  final name = 'generator/${file.uri.pathSegments.last}';
  final Object? rules;
  try {
    rules = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    return (seed: null, problems: ['$name: invalid JSON: ${e.message}']);
  }
  final (:problems, :options) = await validate(file.path);
  if (problems.isNotEmpty) {
    return (
      seed: null,
      problems: [for (final problem in problems) '$name: $problem'],
    );
  }
  if (options == null) {
    throw RulesValidatorException('The validator gave no options.');
  }
  return (
    seed: RulesSeed(rules! as Map<String, Object?>, options),
    problems: const <String>[],
  );
}

/// Writes [seed] as version 1 in one commit unless rules exist (the admin
/// panel owns them from then on); the line for the summary.
Future<String> seedRules(
  RulesSeed seed, {
  required String databasePath,
  required Future<bool> Function() rulesExist,
  required Future<void> Function(List<Map<String, Object?>> writes) commit,
  required bool dryRun,
}) async {
  if (await rulesExist()) {
    return 'Generator rules exist; left as they are (the admin panel owns '
        'them).';
  }
  if (!dryRun) await commit(seed.writes(databasePath));
  return '${dryRun ? 'Would write' : 'Wrote'} generator rules version 1 '
      '(generator/rules, generator/rules/versions/1, generator/options).';
}
