// Prints the coverage audit of the live exercise library in
// content/exercises/*.json (tool/src/content_coverage.dart).
//
// Run from the app root: dart run tool/coverage_report.dart [content dir]
// Exits non-zero when the files do not validate or the generator rule
// fails.
import 'dart:io';

import 'src/content_coverage.dart';
import 'src/content_validator.dart';

void main(List<String> args) {
  final root = args.isNotEmpty ? args.first : 'content';
  final exercises = Directory('$root/exercises');
  if (!exercises.existsSync()) {
    stderr.writeln('No such directory: ${exercises.path}');
    exit(2);
  }
  final report = validateContent(exercises);
  if (report.errors.isNotEmpty) {
    stderr.writeln(
      '${report.errors.length} validation error(s); '
      'run tool/validate_content.dart.',
    );
    exit(1);
  }
  stdout.write(coverageReport(report.live));
  final failed = shortfalls(generatorCoverage(report.live));
  if (failed.isNotEmpty) {
    stderr.writeln('FAILED: ${failed.length} profile × muscle cell(s) short.');
    exit(1);
  }
  stdout.writeln('OK');
}
