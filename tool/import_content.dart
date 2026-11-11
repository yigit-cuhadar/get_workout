// Imports content/exercises/*.json into Firestore `exercises/<id>`.
//
// Run from the app root, with a token that may write Firestore:
//   GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) \
//     dart run tool/import_content.dart --project <id> [--dry-run]
//
// Validates first and refuses to import on any error. Writes only new or
// changed exercises, so unchanged documents keep their `updatedAt`. Never
// deletes; exercises missing from the files are listed as warnings.
import 'dart:io';

import 'src/content_validator.dart';
import 'src/exercise_import.dart';
import 'src/firestore_rest.dart';

const _usage =
    'Usage: GOOGLE_ACCESS_TOKEN=... '
    'dart run tool/import_content.dart --project <id> [--dry-run]';

Future<void> main(List<String> args) async {
  String? project;
  var dryRun = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--project' when i + 1 < args.length:
        project = args[++i];
      case '--dry-run':
        dryRun = true;
      default:
        _fail(_usage);
    }
  }
  if (project == null || project.isEmpty) _fail(_usage);
  final token = Platform.environment['GOOGLE_ACCESS_TOKEN'] ?? '';
  if (token.isEmpty) _fail('GOOGLE_ACCESS_TOKEN is not set.\n$_usage');

  final dir = Directory('content/exercises');
  if (!dir.existsSync()) _fail('No such directory: ${dir.path}');
  final report = validateContent(dir);
  if (report.errors.isNotEmpty) {
    printReport(report);
    _fail('Validation failed; nothing imported.');
  }
  stdout.writeln('Validation OK: ${report.exercises.length} exercises.');

  final docs = {
    for (final e in report.exercises) e.id: ExerciseDoc.fromJson(e.data),
  };
  final firestore = FirestoreRest(project, token);
  try {
    final remote = await firestore.readField('exercises', 'contentHash');
    final plan = planImport({
      for (final doc in docs.values) doc.id: doc.hash,
    }, remote);

    if (!dryRun) {
      final writes = [
        for (final id in plan.toWrite)
          exerciseWrite(firestore.databasePath, docs[id]!),
      ];
      for (final batch in batches(writes)) {
        await firestore.commit(batch);
      }
    }
    _printPlan(plan, project: project, dryRun: dryRun);
  } on FirestoreApiException catch (e) {
    _fail('$e');
  } on SocketException catch (e) {
    _fail('Network error: ${e.message}');
  } finally {
    firestore.close();
  }
}

void _printPlan(
  ImportPlan plan, {
  required String project,
  required bool dryRun,
}) {
  final verb = dryRun ? 'Would write' : 'Wrote';
  stdout.writeln(
    '$verb to $project: ${plan.created.length} created, '
    '${plan.updated.length} updated, ${plan.unchanged.length} unchanged.',
  );
  for (final id in plan.created) {
    stdout.writeln('  created $id');
  }
  for (final id in plan.updated) {
    stdout.writeln('  updated $id');
  }
  for (final id in plan.orphaned) {
    stdout.writeln(
      'WARNING $id is in Firestore but not in the files; not deleted. '
      'Exercises are retired by setting status in their file, not removed.',
    );
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
