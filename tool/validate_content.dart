// Validates the exercise library in content/exercises/*.json.
//
// Run from the app root: dart run tool/validate_content.dart [dir]
// Exits non-zero on any error.
import 'dart:io';

import 'src/content_validator.dart';

void main(List<String> args) {
  final dir = Directory(args.isNotEmpty ? args.first : 'content/exercises');
  if (!dir.existsSync()) {
    stderr.writeln('No such directory: ${dir.path}');
    exit(2);
  }
  final report = validateContent(dir);
  printReport(report);
  if (report.errors.isNotEmpty) exit(1);
  stdout.writeln('OK');
}
