// Imports content/exercises/*.json into Firestore `exercises/<id>` and
// content/programs/*.json into `programs/<id>` (the catalog card) and
// `programs/<id>/detail/main` (the days). See _usage for how it decides what
// to write.
import 'dart:io';

import 'src/content_validator.dart';
import 'src/content_import.dart';
import 'src/firestore_rest.dart';

const _usage = '''
Usage: GOOGLE_ACCESS_TOKEN=\$(gcloud auth print-access-token) \\
         dart run tool/import_content.dart --project <id> [--dry-run] [--force]

Run from the app root. Validates content/exercises/*.json and
content/programs/*.json and refuses to import on any error. Firestore is the
source of truth once seeded; the files are the seed and the bulk-edit path.

A program file becomes two documents: programs/<id> (every field but days)
and programs/<id>/detail/main (days). Exercises are written before programs.

Writes only new documents and ones whose file changed. Each import stores a
contentHash with the document. The admin panel leaves contentHash untouched,
so a document edited there no longer matches it and counts as "edited
elsewhere": it is skipped, listed, and the run exits non-zero. --force
overwrites such documents with the file. A panel that wants a document managed
by this import again must store the matching contentHash itself. A program
is one unit: if its card or its detail was edited elsewhere, neither is
written (without --force), and the two are always in the same commit.

Every write carries a precondition (the document's updateTime from the read,
or "does not exist" for a new one), so a concurrent edit fails the commit
instead of being lost. Nothing is ever deleted; documents missing from the
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

  final exercises = Directory('content/exercises');
  final programs = Directory('content/programs');
  for (final dir in [exercises, programs]) {
    if (!dir.existsSync()) _fail('No such directory: ${dir.path}');
  }
  final report = validateContent(exercises, programs: programs);
  if (report.errors.isNotEmpty) {
    printReport(report);
    _fail('Validation failed; nothing imported.');
  }
  stdout.writeln(
    'Validation OK: ${report.exercises.length} exercises, '
    '${report.programs.length} programs.',
  );

  final docs = {
    for (final doc in [
      for (final e in report.exercises) ContentDoc.exercise(e.data),
      for (final (:card, :detail) in report.programs.map(
        (p) => programDocs(p.data),
      )) ...[card, detail],
    ])
      doc.path: doc,
  };
  final firestore = FirestoreRest(project, token);
  try {
    final remote = <String, RemoteDocument>{};
    Future<void> read(String collection) async {
      for (final d in await firestore.listDocuments(collection)) {
        remote['$collection/${d.id}'] = RemoteDocument.fromFields(
          decodeFields(d.fields),
          d.updateTime,
        );
      }
    }

    await read('exercises');
    await read('programs');
    final programIds = {
      for (final p in report.programs) p.id,
      for (final path in remote.keys)
        if (path.startsWith('programs/')) path.split('/')[1],
    };
    for (final id in programIds) {
      await read('programs/$id/detail');
    }
    final plan = planImport(
      {for (final doc in docs.values) doc.path: doc.hash},
      remote,
      force: force,
    );

    if (!dryRun) {
      await firestore.commitInBatches([
        for (final unit in groupByUnit(plan.toWrite))
          [
            for (final path in unit)
              contentWrite(
                firestore.databasePath,
                docs[path]!,
                updateTime: remote[path]?.updateTime,
              ),
          ],
      ]);
    }
    _printPlan(plan, project: project, dryRun: dryRun);
    if (plan.skipped.isNotEmpty) {
      _fail(
        '${plan.skipped.length} document(s) were edited elsewhere and skipped, '
        'with ${plan.held.length} more of the same program(s). Bring the edit '
        'into the file, or run with --force to overwrite.',
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
    '${plan.unchanged.length} unchanged, ${plan.skipped.length} skipped, '
    '${plan.held.length} held back.',
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
  for (final id in plan.held) {
    stdout.writeln(
      'WARNING $id was held back: another document of ${importUnit(id)} was '
      'edited elsewhere.',
    );
  }
  for (final id in plan.orphaned) {
    stdout.writeln(
      'WARNING $id is in Firestore but not in the files; not deleted. '
      'Content is retired by setting status in its file, not removed.',
    );
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
