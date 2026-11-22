// Validates the exercise library in content/exercises/*.json, the programs
// in content/programs/*.json and, when the functions are built, the
// generator rules in content/generator/rules.json, and prints a summary of
// each program.
//
// Run from the app root: dart run tool/validate_content.dart [content dir]
// Exits non-zero on any error.
import 'dart:io';

import 'src/content_validator.dart';
import 'src/rules_seed.dart';

Future<void> main(List<String> args) async {
  final root = args.isNotEmpty ? args.first : 'content';
  final exercises = Directory('$root/exercises');
  final programs = Directory('$root/programs');
  for (final dir in [exercises, programs]) {
    if (!dir.existsSync()) {
      stderr.writeln('No such directory: ${dir.path}');
      exit(2);
    }
  }
  final report = validateContent(exercises, programs: programs);
  final rules = File('$root/generator/rules.json');
  if (rules.existsSync() && !File(rulesCliPath).existsSync()) {
    stdout.writeln(
      'Generator rules not checked: $rulesCliPath is missing (run '
      '`npm run build` in functions/).',
    );
  } else if (rules.existsSync()) {
    try {
      report.errors.addAll(
        (await loadRulesSeed(rules, validateRulesWithNode)).problems,
      );
    } on RulesValidatorException catch (e) {
      report.errors.add('$e');
    }
  }
  printReport(report);
  if (report.errors.isNotEmpty) exit(1);
  stdout.writeln('OK');
}
