// Imports content/exercises/*.json into Firestore `exercises/<id>`.
// See _usage for how it decides what to write.
import 'dart:io';

import 'src/content_validator.dart';
import 'src/exercise_import.dart';
import 'src/firestore_rest.dart';

const _usage = '''
Usage: GOOGLE_ACCESS_TOKEN=\$(gcloud auth print-access-token) \\
         dart run tool/import_content.dart --project <id> [--dry-run] [--force]

Run from the app root. Validates content/exercises/*.json and refuses to
import on any error. Firestore is the source of truth once seeded; the files
are the seed and the bulk-edit path.

Writes only new exercises and ones whose file changed. Each import stores a
contentHash with the document. The admin panel leaves contentHash untouched,
so a document edited there no longer matches it and counts as "edited
elsewhere": it is skipped, listed, and the run exits non-zero. --force
overwrites such documents with the file. A panel that wants a document managed
by this import again must store the matching contentHash itself.

Every write carries a precondition (the document's updateTime from the read,
or "does not exist" for a new one), so a concurrent edit fails the commit
instead of being lost. Nothing is ever deleted; exercises missing from the
files are listed as warnings (retire one by setting its status in its file).

--dry-run prints the same summary without writing.''';

Future<void> main(List<String> args) async {
  String? project;
  var dryRun = false, force = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--project' when i + 1 < args.length:
        project = args[++i];
      case '--dry-run':
        dryRun = true;
      case '--force':
        force = true;
      default:
        _fail(_usage);
    }
  }
  if (project == null || project.isEmpty) _fail(_usage);
  final token = Platform.environment['GOOGLE_ACCESS_TOKEN'] ?? '';
  if (token.isEmpty) _fail('GOOGLE_ACCESS_TOKEN is not set.\n\n$_usage');

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
    final remote = {
      for (final d in await firestore.listDocuments('exercises'))
        d.id: RemoteExercise.fromFields(decodeFields(d.fields), d.updateTime),
    };
    final plan = planImport(
      {for (final doc in docs.values) doc.id: doc.hash},
      remote,
      force: force,
    );

    if (!dryRun) {
      await firestore.commitInBatches([
        for (final id in plan.toWrite)
          exerciseWrite(
            firestore.databasePath,
            docs[id]!,
            updateTime: remote[id]?.updateTime,
          ),
      ]);
    }
    _printPlan(plan, project: project, dryRun: dryRun);
    if (plan.skipped.isNotEmpty) {
      _fail(
        '${plan.skipped.length} exercise(s) were edited elsewhere and skipped. '
        'Bring the edit into the file, or run with --force to overwrite.',
      );
    }
  } on PartialCommitException catch (e) {
    final cause = e.cause;
    final why = cause is FirestoreApiException && cause.preconditionFailed
        ? 'A document changed since it was read (precondition failed), so '
              'that commit wrote nothing. Run the import again.\n$cause'
        : '$cause';
    _fail(
      '$why\n${e.written} document(s) were written by earlier commits; '
      'the rest were not written.',
    );
  } on FirestoreException catch (e) {
    _fail('$e');
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
  final overwritten = plan.force ? plan.edited.length : 0;
  stdout.writeln(
    '$verb to $project: ${plan.created.length} created, '
    '${plan.updated.length} updated, $overwritten overwritten, '
    '${plan.unchanged.length} unchanged, ${plan.skipped.length} skipped.',
  );
  for (final id in plan.created) {
    stdout.writeln('  created $id');
  }
  for (final id in plan.updated) {
    stdout.writeln('  updated $id');
  }
  for (final id in plan.edited) {
    stdout.writeln(
      plan.force
          ? '  overwritten $id (was edited elsewhere)'
          : 'WARNING $id was edited elsewhere and differs from its file; '
                'skipped.',
    );
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
