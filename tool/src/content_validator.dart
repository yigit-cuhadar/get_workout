// Validates the exercise library in content/exercises/*.json against the
// content rules shared with the app (lib/features/exercises/domain/
// content_rules.dart), then checks the library as a whole.
//
// Used by tool/validate_content.dart and tool/import_content.dart.
import 'dart:convert';
import 'dart:io';

import 'package:get_workout/features/exercises/domain/content_rules.dart';

/// What [validateContent] found in a content directory.
class ContentReport {
  final perFile = <String, int>{};
  final exercises = <ExerciseEntry>[];
  final errors = <String>[];
  final warnings = <String>[];
  String coverage = '';

  // Draft and retired exercises are not shown to users, so popularity,
  // family ranks and coverage only count live ones.
  List<ExerciseEntry> get live => exercises.where((e) => e.isLive).toList();
}

/// Reads every `*.json` file in [dir] (which must exist) and checks it.
ContentReport validateContent(Directory dir) {
  final report = ContentReport();
  final errors = report.errors;
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      errors.add('$name: invalid JSON: ${e.message}');
      continue;
    }
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
  return report;
}

/// Prints the file counts, coverage, warnings and errors of [report].
void printReport(ContentReport report) {
  stdout.writeln('Files:');
  report.perFile.forEach((file, count) => stdout.writeln('  $file: $count'));
  stdout.writeln(
    'Total: ${report.exercises.length} (live: ${report.live.length})',
  );
  stdout.writeln(report.coverage);
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
