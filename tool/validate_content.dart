// Validates the exercise library in content/exercises/*.json and the
// programs in content/programs/*.json, and prints a summary of each program.
//
// Run from the app root: dart run tool/validate_content.dart [content dir]
// Exits non-zero on any error.
import 'dart:io';

import 'src/content_validator.dart';

void main(List<String> args) {
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
  printReport(report);
  if (report.errors.isNotEmpty) exit(1);
  stdout.writeln('OK');
}
