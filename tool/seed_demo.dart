// Seeds a dev account with demo data, so store screenshots show a lived-in
// account. See _usage.
import 'dart:io';

import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import 'src/content_import.dart' show decodeFields;
import 'src/content_validator.dart';
import 'src/demo_seed.dart';
import 'src/firestore_rest.dart';

const _project = 'getworkout-dev';

const _usage =
    '''
Usage: GOOGLE_ACCESS_TOKEN=\$(gcloud auth print-access-token) \\
         dart run tool/seed_demo.dart --project $_project --uid <uid> \\
         [--dry-run] [--clear]

Run from the app root. Only for $_project. Writes, for that user, eight
weeks ending today: the onboarding answers (onboarding complete), an active
copy of the ready-made "Upper/Lower 4-Day" program trained Mon, Tue, Thu and
Fri, about 30 of its workouts with rising weights, the exercise stats
rebuilt from them, weigh-ins and four measurement days, three cardio
sessions and a few favourite exercises. No photos.

Every document it creates has an id starting with "$demoPrefix", so a new
run replaces the last one's. Exercise stats are rebuilt from the demo
workouts and any other workouts of the user.

--clear removes what the tool wrote instead: the "$demoPrefix" documents, the
active program while it is the demo's and the demo favourites; stats are
rebuilt from the user's other workouts. The profile stays.

--dry-run prints what would be written without writing.''';

Future<void> main(List<String> args) async {
  String? project, uid;
  var dryRun = false, clear = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--project' when i + 1 < args.length:
        project = args[++i];
      case '--uid' when i + 1 < args.length:
        uid = args[++i];
      case '--dry-run':
        dryRun = true;
      case '--clear':
        clear = true;
      default:
        _fail(_usage);
    }
  }
  if (project == null || uid == null) _fail(_usage);
  if (project != _project) _fail('Refusing $project: only $_project.');
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(uid)) _fail('Not a uid: $uid');
  final token = Platform.environment['GOOGLE_ACCESS_TOKEN'] ?? '';
  if (token.isEmpty) _fail('GOOGLE_ACCESS_TOKEN is not set.\n\n$_usage');

  final firestore = FirestoreRest(project, token);
  try {
    final demoPaths = <String>{};
    final demoWorkouts = <Workout>[];
    final otherWorkouts = <Workout>[];
    for (final collection in demoCollections) {
      final path = 'users/$uid/$collection';
      for (final doc in await firestore.listDocuments(path)) {
        final demo = doc.id.startsWith(demoPrefix);
        if (demo) demoPaths.add('$path/${doc.id}');
        if (collection != 'workouts') continue;
        final workout = workoutFromDoc(doc.id, decodeFields(doc.fields));
        if (workout == null) {
          stdout.writeln('WARNING unreadable workout ${doc.id} left out.');
        } else {
          (demo ? demoWorkouts : otherWorkouts).add(workout);
        }
      }
    }
    final existing = (demoPaths: demoPaths, otherWorkouts: otherWorkouts);

    final List<Map<String, Object?>> writes;
    final String summary;
    if (clear) {
      final user = await firestore.getDocument('users/$uid');
      final active = user == null ? null : decodeFields(user)['activeProgram'];
      final programId = active is Map ? active['programId'] : null;
      writes = clearWrites(
        firestore.databasePath,
        uid,
        existing,
        (exists: user != null, activeProgramId: programId as String?),
        demoExerciseIds: {for (final w in demoWorkouts) ...w.exerciseIds},
      );
      summary =
          '${demoPaths.length} demo documents removed'
          '${programId == demoProgramId ? ', active program stopped' : ''}, '
          'demo favourites removed, stats rebuilt from '
          '${otherWorkouts.length} other workouts.';
    } else {
      final content = validateContent(
        Directory('content/exercises'),
        programs: Directory('content/programs'),
      );
      if (content.errors.isNotEmpty) {
        printReport(content);
        _fail('Content does not validate; nothing written.');
      }
      final (:program, :catalogue) = demoContent(content);
      final seed = buildDemoSeed(
        today: CalendarDate.of(DateTime.now()),
        programJson: program,
        catalogue: catalogue,
      );
      writes = seedWrites(firestore.databasePath, uid, seed, existing);
      final next = seed.active;
      summary =
          '${seed.workouts.length} workouts from '
          '${CalendarDate.of(seed.workouts.first.startedAt)} to '
          '${CalendarDate.of(seed.workouts.last.startedAt)}, '
          'stats of ${seed.exerciseIds.length} exercises, '
          '${seed.bodyEntries.length} body entries '
          '(${seed.bodyEntries.where((e) => !e.isWeightOnly).length} '
          'measurement days), ${seed.cardio.length} cardio sessions, '
          'profile, favourites and the program, next day '
          '${seed.program.days[next.nextDayIndex].name} on ${next.nextDate}.';
    }
    if (!dryRun) {
      await firestore.commitInBatches([
        for (final write in writes) [write],
      ]);
    }
    stdout.writeln(
      '${dryRun ? 'Would write' : 'Wrote'} ${writes.length} writes to '
      'users/$uid on $project: $summary',
    );
  } on PartialCommitException catch (e) {
    _fail(
      '${e.cause}\n${e.written} writes were made by earlier commits; '
      'run the tool again.',
    );
  } on FirestoreException catch (e) {
    _fail('$e');
  } finally {
    firestore.close();
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
