// Validates the exercise library in content/exercises/*.json and the
// programs in content/programs/*.json against the content rules shared with
// the app (lib/features/exercises/domain/content_rules.dart and
// program_rules.dart), then checks the library and the catalogue as wholes.
//
// Used by tool/validate_content.dart and tool/import_content.dart.
import 'dart:convert';
import 'dart:io';

import 'package:get_workout/features/exercises/domain/content_rules.dart';
import 'package:get_workout/features/exercises/domain/program_rules.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

/// What [validateContent] found in a content directory.
class ContentReport {
  final perFile = <String, int>{};
  final exercises = <ExerciseEntry>[];
  final programs = <ProgramEntry>[];
  final errors = <String>[];
  final warnings = <String>[];
  String coverage = '';

  // Draft and retired exercises are not shown to users, so popularity,
  // family ranks and coverage only count live ones.
  List<ExerciseEntry> get live => exercises.where((e) => e.isLive).toList();

  /// Every exercise by id; a repeated id keeps its last entry.
  Map<String, ExerciseEntry> get library => {
    for (final e in exercises) e.id: e,
  };
}

/// Reads every `*.json` file in [exercises] (which must exist) and checks
/// it; with [programs], also every program file there against the library.
ContentReport validateContent(Directory exercises, {Directory? programs}) {
  final report = ContentReport();
  final errors = report.errors;
  for (final (name, decoded) in _readJson(exercises, errors)) {
    if (decoded is! List) {
      errors.add('$name: top level must be a JSON array');
      continue;
    }
    report.perFile[name] = decoded.length;
    for (final (i, item) in decoded.indexed) {
      if (item is! Map<String, Object?>) {
        errors.add('$name: item $i is not an object');
        continue;
      }
      final exercise = ExerciseEntry(item, file: name);
      for (final problem in exerciseProblems(item)) {
        errors.add('${exercise.where}: ${problem.message}');
      }
      report.exercises.add(exercise);
    }
  }

  final library = checkLibrary(report.exercises);
  errors.addAll(library.errors);
  report.warnings.addAll(library.warnings);
  report.coverage = library.coverage;
  if (programs != null) _validatePrograms(programs, report);
  return report;
}

/// The decoded `*.json` files of [dir] by file name, sorted; a file that is
/// not JSON is an error and left out.
List<(String, Object?)> _readJson(Directory dir, List<String> errors) {
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final result = <(String, Object?)>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    try {
      result.add((name, jsonDecode(file.readAsStringSync())));
    } on FormatException catch (e) {
      errors.add('$name: invalid JSON: ${e.message}');
    }
  }
  return result;
}

void _validatePrograms(Directory dir, ContentReport report) {
  final errors = report.errors;
  final library = report.library;
  for (final (name, decoded) in _readJson(dir, errors)) {
    if (decoded is! Map<String, Object?>) {
      errors.add('$name: top level must be a JSON object');
      continue;
    }
    final program = ProgramEntry(decoded, file: name);
    if (name != '${program.id}.json') {
      errors.add('${program.where}: file must be named ${program.id}.json');
    }
    for (final problem in programProblems(decoded, library)) {
      errors.add('${program.where}: ${problem.message}');
    }
    report.programs.add(program);
  }
  final catalogue = checkCatalogue(report.programs, library);
  errors.addAll(catalogue.errors);
  report.warnings.addAll(catalogue.warnings);
}

/// Prints the file counts, coverage, warnings and errors of [report].
void printReport(ContentReport report) {
  stdout.writeln('Files:');
  report.perFile.forEach((file, count) => stdout.writeln('  $file: $count'));
  stdout.writeln(
    'Total: ${report.exercises.length} (live: ${report.live.length})',
  );
  stdout.writeln(report.coverage);
  if (report.programs.isNotEmpty) _printPrograms(report);
  for (final warning in report.warnings) {
    stdout.writeln('WARNING $warning');
  }
  for (final error in report.errors) {
    stderr.writeln('ERROR $error');
  }
  if (report.errors.isNotEmpty) {
    stderr.writeln('${report.errors.length} error(s).');
  }
}

void _printPrograms(ContentReport report) {
  final live = report.programs.where((p) => p.isLive);
  final premium = live.where((p) => p.isPremium).length;
  stdout.writeln(
    'Programs: ${report.programs.length} (live: ${live.length}, '
    'free: ${live.length - premium}, premium: $premium)',
  );
  String number(double n) =>
      n == n.roundToDouble() ? '${n.round()}' : n.toStringAsFixed(1);
  for (final program in report.programs) {
    final d = program.data;
    final summary = summarizeProgram(program, report.library);
    stdout
      ..writeln(
        '  ${program.id}: ${program.name} '
        '[${d['status']}, ${program.isPremium ? 'premium' : 'free'}, '
        '${d['level']}, ${d['goal']}, ${d['equipmentProfile']}, '
        '${program.days.length} days]',
      )
      ..writeln('    minutes per day: ${summary.minutesPerDay.join(', ')}')
      ..writeln(
        '    weekly sets: ${[for (final m in Muscle.values)
          if (summary.weeklySets[m] case final sets?) '${m.code} ${number(sets)}'].join(', ')}',
      );
  }
  stdout.writeln();
}
