// Pure parts of tool/seed_demo.dart: a lived-in demo account (profile, an
// active copy of a ready-made program, about eight weeks of its workouts
// with their exercise stats, body entries, cardio and favourites), built
// with the app's own domain code and turned into the documents its
// repositories write.
import 'dart:math' as math;

import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/exercises/data/exercise_map.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/catalogue_rules.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/data/workout_maps.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/set_logging.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_editing.dart';
import 'package:get_workout/features/workout/domain/warmups.dart';

import 'content_validator.dart';

/// Every document the tool writes in a collection has an id starting with
/// this, so `--clear` finds them again.
const demoPrefix = 'demo_';

/// The ready-made program the demo follows, and the id of its copy.
const sourceProgramId = 'pr_upper_lower_4_day';
const demoProgramId = '${demoPrefix}upper_lower_4_day';

/// Monday Upper 1, Tuesday Lower 1, Thursday Upper 2, Friday Lower 2.
const demoSchedule = {1: 0, 2: 1, 4: 2, 5: 3};

/// How long ago the program was started.
const demoDays = 56;

/// Program sessions left out, by position, so the history is not perfect.
const skippedSessions = {6, 21};

const demoFavorites = [
  'ex_barbell_bench_press',
  'ex_barbell_back_squat',
  'ex_barbell_deadlift',
  'ex_pull_up',
  'ex_romanian_deadlift',
];

/// The collections under `users/{uid}` holding demo documents.
const demoCollections = ['workouts', 'bodyEntries', 'cardio', 'programs'];

/// Onboarding answers, as `users/{uid}.profile` stores them.
final demoProfile = <String, Object?>{
  'goal': Goal.buildMuscle.code,
  'level': Level.intermediate.code,
  'daysPerWeek': 4,
  'equipment': [
    for (final item in Equipment.values)
      if (EquipmentProfile.fullGym.equipment.contains(item)) item.code,
  ],
  'sex': Sex.male.code,
  'birthYear': 1994,
  'heightCm': 180.0,
  'weightKg': 82.0,
  'targetWeightKg': 78.0,
};

/// The load of an exercise over the run, from [startKg] to [endKg] in
/// steps of [stepKg] (for an exercise logged by reps alone, the reps go
/// from the bottom of the program's range to the top instead).
typedef LoadPlan = ({double startKg, double endKg, double stepKg});

const loadPlans = <String, LoadPlan>{
  // Upper 1
  'ex_barbell_bench_press': (startKg: 70, endKg: 82.5, stepKg: 2.5),
  'ex_barbell_row': (startKg: 60, endKg: 72.5, stepKg: 2.5),
  'ex_seated_dumbbell_shoulder_press': (startKg: 20, endKg: 26, stepKg: 2),
  'ex_lat_pulldown': (startKg: 55, endKg: 70, stepKg: 5),
  'ex_dumbbell_lateral_raise': (startKg: 8, endKg: 12, stepKg: 1),
  'ex_ez_bar_curl': (startKg: 30, endKg: 37.5, stepKg: 2.5),
  'ex_triceps_pushdown': (startKg: 25, endKg: 32.5, stepKg: 2.5),
  // Lower 1
  'ex_barbell_back_squat': (startKg: 95, endKg: 115, stepKg: 5),
  'ex_romanian_deadlift': (startKg: 80, endKg: 95, stepKg: 2.5),
  'ex_leg_press': (startKg: 140, endKg: 170, stepKg: 5),
  'ex_lying_leg_curl': (startKg: 35, endKg: 45, stepKg: 5),
  'ex_standing_calf_raise': (startKg: 60, endKg: 75, stepKg: 5),
  'ex_cable_crunch': (startKg: 30, endKg: 40, stepKg: 2.5),
  // Upper 2
  'ex_incline_dumbbell_press': (startKg: 26, endKg: 32, stepKg: 2),
  // Added weight.
  'ex_pull_up': (startKg: 2.5, endKg: 10, stepKg: 2.5),
  'ex_seated_cable_row': (startKg: 55, endKg: 70, stepKg: 5),
  'ex_cable_crossover': (startKg: 12.5, endKg: 17.5, stepKg: 2.5),
  'ex_cable_lateral_raise': (startKg: 5, endKg: 10, stepKg: 2.5),
  'ex_face_pull': (startKg: 20, endKg: 27.5, stepKg: 2.5),
  'ex_incline_dumbbell_curl': (startKg: 10, endKg: 14, stepKg: 1),
  'ex_cable_overhead_triceps_extension': (
    startKg: 20,
    endKg: 27.5,
    stepKg: 2.5,
  ),
  // Lower 2
  'ex_barbell_deadlift': (startKg: 120, endKg: 140, stepKg: 5),
  'ex_bulgarian_split_squat': (startKg: 16, endKg: 22, stepKg: 2),
  'ex_leg_extension': (startKg: 45, endKg: 60, stepKg: 5),
  'ex_seated_leg_curl': (startKg: 40, endKg: 50, stepKg: 5),
  'ex_seated_calf_raise': (startKg: 40, endKg: 55, stepKg: 5),
};

/// The first [warmedUpExercises] exercises of a day get the warm-ups the
/// default settings add; the rest are left untouched, so finishing drops
/// them, as it does for a user who skips them.
const warmedUpExercises = 2;

/// Measurements in cm on the first and the last measurement day; the days
/// between lie on the line. With the profile's height and sex, neck and
/// abdomen give a body fat of about 19.5 % falling to 16.5 %.
const measurementRange = <BodyMeasurement, (double, double)>{
  BodyMeasurement.neck: (39.5, 39),
  BodyMeasurement.shoulders: (121, 122.5),
  BodyMeasurement.chest: (104, 105.5),
  BodyMeasurement.waist: (88, 84.5),
  BodyMeasurement.abdomen: (91, 86.5),
  BodyMeasurement.hips: (101, 99.5),
  BodyMeasurement.leftUpperArm: (36, 37),
  BodyMeasurement.rightUpperArm: (36.5, 37.5),
  BodyMeasurement.leftForearm: (30, 30.5),
  BodyMeasurement.rightForearm: (30.5, 31),
  BodyMeasurement.leftThigh: (59, 60),
  BodyMeasurement.rightThigh: (59.5, 60.5),
  BodyMeasurement.leftCalf: (38.5, 38.5),
  BodyMeasurement.rightCalf: (38.5, 39),
};

/// Body weight on the first and the last weigh-in.
const weightRange = (85.5, 82.0);

/// Days between weigh-ins.
const weighInEveryDays = 3;

/// Day to day ups and downs of the weigh-ins between the first and the
/// last, in kg.
const weightNoise = [0.2, -0.1, 0.1, -0.2, 0.3, 0.0, -0.1];

/// Weigh-ins, by position, that are also measurement days; the last one is
/// always one.
const measurementWeighIns = {0, 6, 12};

/// Everything the demo account holds, by the app's own entities.
class DemoSeed {
  DemoSeed({
    required this.program,
    required this.active,
    required this.workouts,
    required this.bodyEntries,
    required this.cardio,
  });

  final Program program;
  final ActiveProgram active;

  /// Oldest first.
  final List<Workout> workouts;
  final List<BodyEntry> bodyEntries;
  final List<CardioSession> cardio;

  /// Every exercise the workouts do.
  Set<String> get exerciseIds => {
    for (final workout in workouts) ...workout.exerciseIds,
  };
}

/// The [sourceProgramId] file of validated content [report], and the
/// exercises it uses.
({Map<String, Object?> program, Map<String, Exercise> catalogue}) demoContent(
  ContentReport report,
) {
  final program = report.programs
      .firstWhere(
        (p) => p.id == sourceProgramId,
        orElse: () => throw StateError('no program $sourceProgramId'),
      )
      .data;
  final library = report.library;
  return (
    program: program,
    catalogue: {
      for (final day in ProgramEntry(program).program.days)
        for (final item in day.items)
          item.exerciseId: exerciseFromMap(
            item.exerciseId,
            library[item.exerciseId]!.data,
          ),
    },
  );
}

/// The demo account as of [today], following ready-made program
/// [programJson] (a `content/programs/*.json` file) with the exercises of
/// [catalogue].
DemoSeed buildDemoSeed({
  required CalendarDate today,
  required Map<String, Object?> programJson,
  required Map<String, Exercise> catalogue,
}) {
  final entry = ProgramEntry(programJson);
  if (entry.id != sourceProgramId || entry.isPremium) {
    throw ArgumentError.value(entry.id, 'programJson', 'not $sourceProgramId');
  }
  final source = entry.program;
  final program = Program(
    id: demoProgramId,
    name: source.name,
    origin: source.origin,
    sourceId: source.sourceId,
    lengthWeeks: source.lengthWeeks,
    days: source.days,
  );
  final start = today.addDays(-demoDays);
  final started = ProgramSchedule.start(
    programId: demoProgramId,
    schedule: demoSchedule,
    today: start,
    startedAt: _at(start, 8, 10),
  );
  final dates = sessionDates(start: started.nextDate, today: today);
  final workouts = _workouts(program, catalogue, dates);
  final last = CalendarDate.of(workouts.last.startedAt);
  final schedule = ProgramSchedule(started, dayCount: program.days.length);
  return DemoSeed(
    program: program,
    active: schedule.complete(on: last),
    workouts: workouts,
    bodyEntries: bodyEntries(start: start, today: today),
    cardio: cardioSessions(today),
  );
}

/// The training days from [start] up to the day before [today], but the
/// [skippedSessions].
List<CalendarDate> sessionDates({
  required CalendarDate start,
  required CalendarDate today,
}) {
  final training = [
    for (var date = start; date.isBefore(today); date = date.addDays(1))
      if (demoSchedule.containsKey(date.weekday)) date,
  ];
  return [
    for (final (i, date) in training.indexed)
      if (!skippedSessions.contains(i)) date,
  ];
}

/// The load of the [n]th of [count] sessions of an exercise: [plan]'s
/// start, rising in whole steps evenly to its end on the last one.
double loadOn(LoadPlan plan, int n, int count) {
  final steps = ((plan.endKg - plan.startKg) / plan.stepKg).round();
  final level = count < 2 ? steps : steps * n ~/ (count - 1);
  return plan.startKg + level * plan.stepKg;
}

/// The reps of set [set] of the [n]th of [count] sessions of [item] at
/// [kg], [sinceIncrease] sessions after the load last went up: one above the
/// bottom of the range on a new load, one more each session it stays,
/// one fewer on the last set of three or more. Reps alone ([kg] null) climb
/// through the range over the run.
int repsOn(
  ProgramItem item,
  int set, {
  required int n,
  required int count,
  required double? kg,
  required int sinceIncrease,
}) {
  final low = item.repMin ?? item.repMax ?? 8;
  final high = item.repMax ?? low;
  if (kg == null) {
    return count < 2 ? high : low + (high - low) * n ~/ (count - 1);
  }
  final top = math.min(high, low + 1 + sinceIncrease);
  final tired = item.sets >= 3 && set == item.sets - 1 ? 1 : 0;
  return math.max(low, top - tired);
}

List<Workout> _workouts(
  Program program,
  Map<String, Exercise> catalogue,
  List<CalendarDate> dates,
) {
  final days = [for (final date in dates) demoSchedule[date.weekday]!];
  final counts = <int, int>{};
  for (final day in days) {
    counts[day] = (counts[day] ?? 0) + 1;
  }
  final seen = <int, int>{};
  final previousKg = <String, double>{};
  final sinceIncrease = <String, int>{};
  return [
    for (final (i, date) in dates.indexed)
      () {
        final dayIndex = days[i];
        final n = seen[dayIndex] = (seen[dayIndex] ?? -1) + 1;
        final day = program.days[dayIndex];
        final startedAt = _at(date, 18, (i * 17) % 75);
        final planned = workoutFromProgramDay(
          id: '${demoPrefix}w${(i + 1).toString().padLeft(2, '0')}',
          startedAt: startedAt,
          name: '${program.name} · ${day.name}',
          program: program,
          dayIndex: dayIndex,
          catalogue: catalogue,
          language: Exercise.fallbackLanguage,
          warmups: const WarmupSettings(),
        );
        final exercises = [
          for (final (e, exercise) in planned.exercises.indexed)
            () {
              final id = exercise.exerciseId;
              final plan = loadPlans[id];
              final kg = plan == null
                  ? null
                  : loadOn(plan, n, counts[dayIndex]!);
              final since = kg != null && kg == previousKg[id]
                  ? sinceIncrease[id]! + 1
                  : 0;
              if (kg != null) {
                previousKg[id] = kg;
                sinceIncrease[id] = since;
              }
              return _logged(
                exercise,
                kg: kg,
                warmUp: e < warmedUpExercises,
                reps: (set) => repsOn(
                  exercise.goal!,
                  set,
                  n: n,
                  count: counts[dayIndex]!,
                  kg: kg,
                  sinceIncrease: since,
                ),
              );
            }(),
        ];
        return finishWorkout(
          planned.copyWith(exercises: exercises),
          startedAt.add(sessionLength(day, i)),
        );
      }(),
  ];
}

/// [exercise] with its working sets done at [kg] for [reps], easy first
/// and harder towards the end, and with [warmUp] its warm-ups done at the
/// weights the app suggests for them.
WorkoutExercise _logged(
  WorkoutExercise exercise, {
  required double? kg,
  required bool warmUp,
  required int Function(int set) reps,
}) {
  final working = exercise.sets.where((set) => !set.isWarmup).length;
  var w = 0;
  var s = 0;
  return exercise.copyWith(
    sets: [
      for (final set in exercise.sets)
        if (set.isWarmup)
          switch (warmUp
              ? rampedWarmup(
                  w++,
                  kg,
                  WeightUnit.kg,
                  WarmupScheme.standard.presetSteps,
                )
              : null) {
            final ramp? => set.copyWith(
              weightKg: () => ramp.weightKg,
              reps: () => ramp.reps,
              done: true,
            ),
            null => set,
          }
        else
          () {
            final index = s++;
            return set.copyWith(
              weightKg: () => kg,
              reps: () => reps(index),
              rir: () => index < working ~/ 2 ? 2 : 1,
              done: true,
            );
          }(),
    ],
  );
}

/// How long a session of [day] takes: each set with its rest, warm-ups and
/// setting up, give or take a few minutes by [salt].
Duration sessionLength(ProgramDay day, int salt) {
  final sets = day.items.fold(
    0,
    (sum, item) => sum + item.sets * (40 + item.restS),
  );
  return Duration(seconds: sets + 8 * 60 + ((salt * 7) % 9 - 4) * 60);
}

/// A weigh-in every [weighInEveryDays] from [start] to before [today],
/// falling from [weightRange]'s first to its last value, with a little day
/// to day noise; [measurementWeighIns] and the last one are measurement
/// days too.
List<BodyEntry> bodyEntries({
  required CalendarDate start,
  required CalendarDate today,
}) {
  final dates = [
    for (
      var date = start;
      date.isBefore(today);
      date = date.addDays(weighInEveryDays)
    )
      date,
  ];
  final last = dates.length - 1;
  final (first, end) = weightRange;
  return [
    for (final (i, date) in dates.indexed)
      BodyEntry(
        id: '${demoPrefix}b${(i + 1).toString().padLeft(2, '0')}',
        date: _at(date, 7, 30 + (i * 7) % 20),
        weightKg: _round(
          first +
              (end - first) * i / last +
              (i == 0 || i == last ? 0 : weightNoise[i % weightNoise.length]),
          0.1,
        ),
        measurements: measurementWeighIns.contains(i) || i == last
            ? {
                for (final MapEntry(key: m, value: (a, b))
                    in measurementRange.entries)
                  m: _round(a + (b - a) * i / last, 0.5),
              }
            : const {},
      ),
  ];
}

/// Three sessions on the last rest days (Wednesdays and Saturdays) of the
/// two weeks before [today].
List<CardioSession> cardioSessions(CalendarDate today) {
  final dates = [
    for (var d = 14; d >= 1; d--)
      if (today.addDays(-d) case final date
          when date.weekday == DateTime.wednesday ||
              date.weekday == DateTime.saturday)
        date,
  ];
  final picked = dates.sublist(math.max(0, dates.length - 3));
  final kinds = [
    (CardioType.treadmillWalk, 35, 3.2, 270, 118, 8.0),
    (CardioType.stationaryBike, 30, 12.4, 260, 126, null),
    (CardioType.outdoorRun, 28, 5.0, 380, 149, null),
  ];
  return [
    for (final (i, date) in picked.indexed)
      () {
        final (type, minutes, km, kcal, hr, incline) = kinds[i];
        return CardioSession(
          id: '${demoPrefix}c${i + 1}',
          type: type,
          date: date.weekday == DateTime.saturday
              ? _at(date, 10, 30)
              : _at(date, 7, 15),
          duration: Duration(minutes: minutes),
          distanceKm: km,
          calories: kcal,
          avgHeartRate: hr,
          incline: incline,
        );
      }(),
  ];
}

DateTime _at(CalendarDate date, int hour, int minute) =>
    DateTime(date.year, date.month, date.day, hour, minute);

double _round(double value, double step) =>
    double.parse(((value / step).round() * step).toStringAsFixed(1));

// Documents, as the app's repositories write them, with DateTime for a
// Firestore timestamp ([encodeDemoFields] turns them into REST values).

/// `users/{uid}/workouts/{id}`, as `FirestoreWorkoutRepository.workoutToMap`.
Map<String, Object?> workoutDoc(Workout workout) => {
  'startedAt': workout.startedAt,
  'finishedAt': workout.finishedAt ?? workout.startedAt,
  'programId': ?workout.programId,
  'dayIndex': ?workout.dayIndex,
  'name': workout.name,
  'note': ?workout.note,
  'exerciseIds': workout.exerciseIds,
  'exercises': [
    for (final exercise in workout.exercises)
      WorkoutMaps.exerciseToMap(exercise),
  ],
};

/// A workout read back from [doc], decoded REST fields (timestamps as
/// `{timestampValue: ...}`); null when it has no start, finish or name.
Workout? workoutFromDoc(String id, Map<String, Object?> doc) {
  final startedAt = _time(doc['startedAt']);
  final finishedAt = _time(doc['finishedAt']);
  final name = doc['name'];
  final exercises = doc['exercises'];
  if (startedAt == null || finishedAt == null || name is! String) return null;
  final programId = doc['programId'];
  return Workout(
    id: id,
    startedAt: startedAt,
    finishedAt: finishedAt,
    programId: programId is String ? programId : null,
    dayIndex: WorkoutMaps.whole(doc['dayIndex']),
    name: name,
    exercises: [
      if (exercises is List)
        for (final exercise in exercises)
          ?WorkoutMaps.exerciseFromMap(exercise),
    ],
  );
}

DateTime? _time(Object? value) => switch (value) {
  {'timestampValue': final String text} => DateTime.tryParse(text)?.toLocal(),
  _ => null,
};

/// `users/{uid}/exerciseStats/{exerciseId}`, as
/// `FirestoreWorkoutRepository.statsToMap`.
Map<String, Object?> statsDoc(ExerciseStats stats) {
  final last = stats.last;
  Map<String, Object?> values(SetValues set) => {
    'weightKg': ?set.weightKg,
    'reps': ?set.reps,
    'durationS': ?set.durationS,
  };
  return {
    'records': {
      for (final MapEntry(key: kind, value: record) in stats.records.entries)
        kind.code: {
          'value': record.value,
          'date': record.date,
          'workoutId': record.workoutId,
          if (record.set case final set?) 'set': values(set),
        },
    },
    if (last != null)
      'last': {
        'date': last.date,
        'workoutId': last.workoutId,
        'sets': [for (final set in last.sets) WorkoutMaps.setToMap(set)],
      },
    'history': [
      for (final point in stats.history)
        {
          'date': point.date,
          'workoutId': point.workoutId,
          'bestE1rmKg': ?point.bestE1rmKg,
          'volumeKg': point.volumeKg,
          if (point.bestSet case final set?) 'set': values(set),
          'workoutName': ?point.workoutName,
        },
    ],
  };
}

/// `users/{uid}/programs/{id}` without `updatedAt` (a server timestamp),
/// as `FirestoreProgramRepository.programToMap`.
Map<String, Object?> programDoc(Program program) => {
  'name': program.name,
  'origin': program.origin.code,
  'sourceId': ?program.sourceId,
  'lengthWeeks': ?program.lengthWeeks,
  'days': [
    for (final day in program.days)
      {
        ...day.extra,
        'name': day.name,
        'items': [
          for (final item in day.items)
            {
              ...item.extra,
              'exerciseId': item.exerciseId,
              'sets': item.sets,
              'repMin': ?item.repMin,
              'repMax': ?item.repMax,
              'durationS': ?item.durationS,
              'restS': item.restS,
              'targetKg': ?item.targetKg,
              'group': ?item.group,
            },
        ],
      },
  ],
  if (program.premium) 'premium': true,
};

/// `users/{uid}.activeProgram`, as `FirestoreProgramRepository.activeToMap`.
Map<String, Object?> activeProgramMap(ActiveProgram active) => {
  'programId': active.programId,
  'schedule': {
    for (final MapEntry(:key, :value) in active.schedule.entries) '$key': value,
  },
  'nextDayIndex': active.nextDayIndex,
  'nextDate': active.nextDate.toIso(),
  if (active.movedFrom case final movedFrom?) 'movedFrom': movedFrom.toIso(),
  'startedAt': active.startedAt,
};

/// `users/{uid}/bodyEntries/{id}`, as `FirestoreBodyRepository.toMap`.
Map<String, Object?> bodyEntryDoc(BodyEntry entry) => {
  'date': entry.date,
  'weightKg': ?entry.weightKg,
  if (entry.measurements.isNotEmpty)
    'measurements': {
      for (final MapEntry(:key, :value) in entry.measurements.entries)
        key.code: value,
    },
  if (entry.photos.isNotEmpty)
    'photos': {
      for (final MapEntry(:key, :value) in entry.photos.entries)
        key.code: value,
    },
};

/// `users/{uid}/cardio/{id}`, as `FirestoreCardioRepository.toMap`.
Map<String, Object?> cardioDoc(CardioSession session) => {
  'type': session.typeCode,
  'date': session.date,
  'durationS': session.duration.inSeconds,
  'distanceKm': ?session.distanceKm,
  'calories': ?session.calories,
  'avgHeartRate': ?session.avgHeartRate,
  'incline': ?session.incline,
  'note': ?session.note,
};

/// A Firestore REST `Value`; a [DateTime] becomes a timestamp.
Map<String, Object?> encodeDemoValue(Object? value, {bool inArray = false}) =>
    switch (value) {
      null => {'nullValue': null},
      bool() => {'booleanValue': value},
      int() => {'integerValue': '$value'},
      double() => {'doubleValue': value},
      String() => {'stringValue': value},
      DateTime() => {'timestampValue': value.toUtc().toIso8601String()},
      List() when inArray => throw ArgumentError.value(
        value,
        'value',
        'Firestore does not allow arrays directly inside arrays',
      ),
      List() => {
        'arrayValue': {
          if (value.isNotEmpty)
            'values': [
              for (final item in value) encodeDemoValue(item, inArray: true),
            ],
        },
      },
      Map() => {
        'mapValue': {
          if (value.isNotEmpty) 'fields': encodeDemoFields(value.cast()),
        },
      },
      _ => throw ArgumentError.value(value, 'value', 'not storable'),
    };

/// Firestore REST `fields` for a document map.
Map<String, Object?> encodeDemoFields(Map<String, Object?> map) => {
  for (final MapEntry(:key, :value) in map.entries) key: encodeDemoValue(value),
};

// The writes of one `documents:commit`.

/// What the user's collections hold now: the paths (below `documents/`) of
/// the demo documents, and the workouts that are not the demo's.
typedef ExistingData = ({Set<String> demoPaths, List<Workout> otherWorkouts});

/// Whether `users/{uid}` exists, and the program id of its active program.
typedef ExistingUser = ({bool exists, String? activeProgramId});

/// The writes that store [seed] for [uid]: its documents, the stats of its
/// exercises rebuilt from its workouts and the user's other ones, the
/// profile, active program and favourites on `users/{uid}`, and the
/// deletion of earlier demo documents it does not replace.
List<Map<String, Object?>> seedWrites(
  String databasePath,
  String uid,
  DemoSeed seed,
  ExistingData existing,
) {
  final user = 'users/$uid';
  final docs = <String, Map<String, Object?>>{
    for (final w in seed.workouts) '$user/workouts/${w.id}': workoutDoc(w),
    for (final e in seed.bodyEntries)
      '$user/bodyEntries/${e.id}': bodyEntryDoc(e),
    for (final c in seed.cardio) '$user/cardio/${c.id}': cardioDoc(c),
  };
  final all = [...seed.workouts, ...existing.otherWorkouts];
  return [
    for (final path in existing.demoPaths.difference(
      docs.keys.toSet(),
    )..remove('$user/programs/$demoProgramId'))
      _delete(databasePath, path),
    for (final MapEntry(key: path, value: fields) in docs.entries)
      _set(databasePath, path, fields),
    {
      ..._set(
        databasePath,
        '$user/programs/$demoProgramId',
        programDoc(seed.program),
      ),
      'updateTransforms': [_now('updatedAt')],
    },
    ..._statsWrites(databasePath, uid, seed.exerciseIds, all),
    {
      'update': {
        'name': '$databasePath/documents/$user',
        'fields': encodeDemoFields({
          'profile': demoProfile,
          'activeProgram': activeProgramMap(seed.active),
        }),
      },
      'updateMask': {
        'fieldPaths': [
          for (final key in demoProfile.keys) 'profile.$key',
          'activeProgram',
        ],
      },
      'updateTransforms': [
        _now('profile.onboardingCompletedAt'),
        {
          'fieldPath': 'favoriteExerciseIds',
          'appendMissingElements': encodeDemoValue(demoFavorites)['arrayValue'],
        },
      ],
    },
  ];
}

/// The writes that remove what [seedWrites] stored for [uid]: the demo
/// documents, the active program while it is the demo's, and the demo
/// favourites; the stats of the demo workouts' exercises are rebuilt from
/// the user's other workouts, or deleted. The profile stays, so the account
/// is not sent back to onboarding.
List<Map<String, Object?>> clearWrites(
  String databasePath,
  String uid,
  ExistingData existing,
  ExistingUser user, {
  required Set<String> demoExerciseIds,
}) => [
  for (final path in existing.demoPaths) _delete(databasePath, path),
  ..._statsWrites(databasePath, uid, demoExerciseIds, existing.otherWorkouts),
  if (user.exists)
    {
      'update': {'name': '$databasePath/documents/users/$uid', 'fields': {}},
      'updateMask': {
        'fieldPaths': [
          if (user.activeProgramId == demoProgramId) 'activeProgram',
        ],
      },
      'updateTransforms': [
        {
          'fieldPath': 'favoriteExerciseIds',
          'removeAllFromArray': encodeDemoValue(demoFavorites)['arrayValue'],
        },
      ],
    },
];

/// The stats of each of [exerciseIds] rebuilt from [workouts], or deleted
/// when none of them does it.
List<Map<String, Object?>> _statsWrites(
  String databasePath,
  String uid,
  Set<String> exerciseIds,
  List<Workout> workouts,
) => [
  for (final id in exerciseIds.toList()..sort())
    switch (rebuildStats(id, workouts)) {
      final stats? => _set(
        databasePath,
        'users/$uid/exerciseStats/$id',
        statsDoc(stats),
      ),
      null => _delete(databasePath, 'users/$uid/exerciseStats/$id'),
    },
];

Map<String, Object?> _set(
  String databasePath,
  String path,
  Map<String, Object?> fields,
) => {
  'update': {
    'name': '$databasePath/documents/$path',
    'fields': encodeDemoFields(fields),
  },
};

Map<String, Object?> _delete(String databasePath, String path) => {
  'delete': '$databasePath/documents/$path',
};

Map<String, Object?> _now(String fieldPath) => {
  'fieldPath': fieldPath,
  'setToServerValue': 'REQUEST_TIME',
};
