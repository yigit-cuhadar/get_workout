// The program generator (SPEC.md, "Program generator"): a week of training
// from the user's answers and the exercise library, on the device.
//
// It works in passes: pick a split, give every trained muscle a weekly
// target of sets, fill each day with exercises for its muscles, trim each
// day to the session length by the app's own [estimateDay], then move sets
// towards the targets as far as the session lengths allow.
import 'dart:math' as math;

import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/exercise_queries.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/catalogue_rules.dart' show majorMuscles;
import '../../programs/domain/program.dart';
import '../../programs/domain/program_editing.dart';
import 'generator_answers.dart';

/// Why no program can be made from the answers.
enum GenerationIssue {
  /// Days per week outside [GeneratorLimits.minDays]..[GeneratorLimits.maxDays].
  daysOutOfRange,

  /// The chosen split needs more days a week ([TrainingSplit.minDays]).
  splitNeedsMoreDays,

  /// A day gets no exercise: the equipment, level, exclusions and the area
  /// to go easy on leave none for its muscles.
  noExercises,
}

final class GenerationFailure extends Failure {
  GenerationFailure(this.issue) : super('cannot generate: ${issue.name}');

  final GenerationIssue issue;
}

class GeneratedDay extends Equatable {
  const GeneratedDay({required this.kind, this.variant, required this.items});

  final DayKind kind;

  /// 0, 1, ... when the week has more than one day of [kind]; else null.
  final int? variant;
  final List<ProgramItem> items;

  @override
  List<Object?> get props => [kind, variant, items];
}

class GeneratedProgram extends Equatable {
  const GeneratedProgram({
    required this.split,
    required this.days,
    required this.targets,
    required this.weeklySets,
    this.uncovered = const {},
  });

  final TrainingSplit split;
  final List<GeneratedDay> days;

  /// The weekly sets aimed for, per trained muscle.
  final Map<Muscle, int> targets;

  /// Sets per muscle in a week: 1 for each main and 0.5 for each secondary
  /// muscle of a set (SPEC.md, "Volume").
  final Map<Muscle, double> weeklySets;

  /// Trained muscles no usable exercise works as a main muscle.
  final Set<Muscle> uncovered;

  /// The program to store: the user's own, editable like any other.
  Program toProgram({
    required String name,
    required String Function(GeneratedDay day) dayName,
  }) => Program(
    name: name,
    origin: ProgramOrigin.generated,
    days: [
      for (final day in days) ProgramDay(name: dayName(day), items: day.items),
    ],
  );

  @override
  List<Object?> get props => [split, days, targets, weeklySets, uncovered];
}

/// The split used for [answers]: the chosen one, or by days and level.
TrainingSplit splitFor(GeneratorAnswers answers) =>
    answers.split ??
    switch (answers.daysPerWeek) {
      <= 3 => TrainingSplit.fullBody,
      4 => TrainingSplit.upperLower,
      _ when answers.level == Level.beginner => TrainingSplit.upperLower,
      _ => TrainingSplit.pushPullLegs,
    };

/// The days of a week of [split] trained [days] times.
List<DayKind> splitDays(TrainingSplit split, int days) => switch (split) {
  TrainingSplit.fullBody => List.filled(days, DayKind.fullBody),
  TrainingSplit.upperLower => [
    for (var i = 0; i < days; i++) i.isEven ? DayKind.upper : DayKind.lower,
  ],
  TrainingSplit.pushPullLegs => [
    DayKind.push,
    DayKind.pull,
    DayKind.legs,
    ...switch (days) {
      4 => [DayKind.upper],
      5 => [DayKind.upper, DayKind.lower],
      6 => [DayKind.push, DayKind.pull, DayKind.legs],
      _ => const <DayKind>[],
    },
  ],
};

/// Weekly sets of a major muscle, by level; inside the 10-20 reference band
/// and each level's catalogue band.
const baseWeeklySets = {
  Level.beginner: 10,
  Level.intermediate: 14,
  Level.advanced: 18,
};

/// The top of the reference band; no muscle is trained directly beyond it.
const maxWeeklySets = 20;

/// Extra weekly sets of a focus muscle.
const focusExtraSets = 4;

/// The weekly sets [answers] aim for per muscle: [baseWeeklySets] for the
/// major muscles, half of it for calves and abs, more for focus muscles, and
/// none for the area to go easy on. Other muscles are trained only through
/// the exercises of these.
Map<Muscle, int> weeklyTargets(GeneratorAnswers answers) {
  final base = baseWeeklySets[answers.level]!;
  final easy = answers.easyArea?.muscles ?? const <Muscle>{};
  return {
    for (final muscle in Muscle.values)
      if (!easy.contains(muscle))
        if (answers.focus.contains(muscle))
          muscle: math.min(base + focusExtraSets, maxWeeklySets)
        else if (majorMuscles.contains(muscle))
          muscle: base
        else if (muscle == Muscle.calf || muscle == Muscle.abdominal)
          muscle: base ~/ 2,
  };
}

/// Every muscle, the most important first: a day's exercises follow it.
const musclePriority = [
  Muscle.quads,
  Muscle.pec,
  Muscle.lat,
  Muscle.hamstring,
  Muscle.glute,
  Muscle.midDelt,
  Muscle.triceps,
  Muscle.biceps,
  Muscle.rearDelt,
  Muscle.calf,
  Muscle.abdominal,
  Muscle.trap,
  Muscle.frontDelt,
  Muscle.oblique,
  Muscle.erector,
  Muscle.forearm,
  Muscle.hipFlexor,
  Muscle.abductor,
  Muscle.adductor,
];

/// Muscles whose first exercise of a day is a compound one; the others'
/// is an isolation exercise.
const _compoundFirst = {
  Muscle.quads,
  Muscle.pec,
  Muscle.lat,
  Muscle.hamstring,
  Muscle.glute,
};

const _minSets = 2;
const _startSets = 3;
const _maxExercisesPerMuscle = 3;
const _minExercisesPerDay = 3;
const _maxExercisesPerDay = 10;

/// Patterns that are not strength work.
const _leftOut = {MovementPattern.mobility, MovementPattern.explosive};

/// Makes a program from [answers] with the [exercises] of the library.
/// Choices between equally good exercises follow [seed], so the same
/// inputs and seed always give the same program, and another seed may give
/// another one.
Result<GeneratedProgram> generateProgram(
  GeneratorAnswers answers,
  List<Exercise> exercises, {
  int seed = 0,
}) {
  final days = answers.daysPerWeek;
  if (days < GeneratorLimits.minDays || days > GeneratorLimits.maxDays) {
    return Err(GenerationFailure(GenerationIssue.daysOutOfRange));
  }
  final split = splitFor(answers);
  if (days < split.minDays) {
    return Err(GenerationFailure(GenerationIssue.splitNeedsMoreDays));
  }
  final generator = _Generator(answers, exercises, seed);
  final kinds = splitDays(split, days);
  final week = [for (final kind in kinds) generator.fill(kind, kinds)];
  if (week.any((day) => day.picks.isEmpty)) {
    return Err(GenerationFailure(GenerationIssue.noExercises));
  }
  generator
    ..fitSessions(week)
    ..raiseToTargets(week)
    ..lowerToTargets(week);
  return Ok(
    GeneratedProgram(
      split: split,
      days: [
        for (final (i, day) in week.indexed)
          GeneratedDay(
            kind: day.kind,
            variant: kinds.where((k) => k == day.kind).length > 1
                ? kinds.take(i).where((k) => k == day.kind).length
                : null,
            items: [for (final pick in day.picks) pick.item],
          ),
      ],
      targets: generator.targets,
      weeklySets: _volume(week),
      uncovered: {
        for (final muscle in generator.targets.keys)
          if (!generator.pool.any((e) => e.mainMuscles.contains(muscle)))
            muscle,
      },
    ),
  );
}

enum _Region { push, pull, legs, core }

_Region _regionOf(Muscle muscle) => switch (muscle) {
  Muscle.pec ||
  Muscle.frontDelt ||
  Muscle.midDelt ||
  Muscle.triceps => _Region.push,
  Muscle.lat ||
  Muscle.trap ||
  Muscle.rearDelt ||
  Muscle.biceps ||
  Muscle.forearm => _Region.pull,
  Muscle.abdominal || Muscle.oblique || Muscle.erector => _Region.core,
  _ => _Region.legs,
};

Set<_Region> _regionsOf(DayKind kind) => switch (kind) {
  DayKind.fullBody => _Region.values.toSet(),
  DayKind.upper => {_Region.push, _Region.pull},
  DayKind.lower || DayKind.legs => {_Region.legs, _Region.core},
  DayKind.push => {_Region.push},
  DayKind.pull => {_Region.pull},
};

class _Pick {
  _Pick(this.exercise, this.template) : sets = template.sets;

  final Exercise exercise;
  final ProgramItem template;
  int sets;

  ProgramItem get item => template.copyWith(sets: sets);
}

class _Day {
  _Day(this.kind);

  final DayKind kind;
  final picks = <_Pick>[];

  Duration get estimate =>
      estimateDay(ProgramDay(items: [for (final pick in picks) pick.item]));
}

class _Generator {
  _Generator(this.answers, List<Exercise> exercises, int seed)
    : _random = math.Random(seed),
      targets = weeklyTargets(answers),
      pool = [
        for (final exercise in exercises)
          if (_usable(exercise, answers)) exercise,
      ]..sort(compareByPopularity),
      _budget = Duration(minutes: answers.sessionMinutes),
      _maxSets = answers.level == Level.beginner ? 4 : 5;

  final GeneratorAnswers answers;
  final math.Random _random;
  final Map<Muscle, int> targets;
  final List<Exercise> pool;
  final Duration _budget;
  final int _maxSets;
  final _used = <String>{};

  Set<Muscle> get _easy => answers.easyArea?.muscles ?? const {};

  /// Catalogue exercises only (a custom one has no level), at most one
  /// level above the user's, as the catalogue rules allow.
  static bool _usable(Exercise e, GeneratorAnswers answers) {
    final level = e.level;
    final easy = answers.easyArea?.muscles ?? const <Muscle>{};
    return level != null &&
        level.index <= answers.level.index + 1 &&
        !_leftOut.contains(e.movementPattern) &&
        !answers.excluded.contains(e.id) &&
        !e.mainMuscles.any(easy.contains) &&
        e.isDoableWith(answers.equipment);
  }

  /// A day of [kind] in a week of [week]: exercises for its muscles, the
  /// most important first, as many as fit the session.
  _Day fill(DayKind kind, List<DayKind> week) {
    final day = _Day(kind);
    final regions = _regionsOf(kind);
    final ordered = [
      ...musclePriority.where(answers.focus.contains),
      ...musclePriority.where((m) => !answers.focus.contains(m)),
    ].where((m) => targets.containsKey(m) && regions.contains(_regionOf(m)));
    double perDay(Muscle muscle) =>
        targets[muscle]! /
        week.where((k) => _regionsOf(k).contains(_regionOf(muscle))).length;
    final slots = [
      for (var rank = 0; rank < _maxExercisesPerMuscle; rank++)
        for (final muscle in ordered)
          if (rank < (perDay(muscle) / _maxSets).ceil()) (muscle, rank),
    ];
    // Sets the day's exercises so far give each muscle as a main one.
    final planned = <Muscle, int>{};
    for (final (muscle, rank) in slots) {
      if (day.picks.length >= _maxExercisesPerDay) break;
      // Already worked enough, e.g. glutes by squats and deadlifts.
      if ((planned[muscle] ?? 0) >= perDay(muscle)) continue;
      final exercise = _pick(muscle, rank, day);
      if (exercise == null) continue;
      day.picks.add(_Pick(exercise, _item(exercise)));
      // Past the session, only the first few stay; [fitSessions] trims them.
      if (day.picks.length > _minExercisesPerDay && day.estimate > _budget) {
        day.picks.removeLast();
        continue;
      }
      _used.add(exercise.id);
      for (final main in exercise.mainMuscles) {
        planned[main] = (planned[main] ?? 0) + _startSets;
      }
    }
    return day;
  }

  Exercise? _pick(Muscle muscle, int rank, _Day day) {
    final onDay = {for (final pick in day.picks) pick.exercise.id};
    final families = {for (final pick in day.picks) pick.exercise.family};
    final patterns = {
      for (final pick in day.picks)
        if (pick.exercise.mainMuscles.contains(muscle))
          pick.exercise.movementPattern,
    };
    final wanted = rank > 0
        ? null
        : _compoundFirst.contains(muscle)
        ? Mechanic.compound
        : Mechanic.isolation;
    int score(Exercise e) =>
        (e.level!.index > answers.level.index ? -3 : 0) +
        (wanted != null && e.mechanic == wanted ? 2 : 0) +
        (e.secondaryMuscles.any(_easy.contains) ? -4 : 0) +
        (families.contains(e.family) ? -2 : 0) +
        (patterns.contains(e.movementPattern) ? -1 : 0) +
        (_used.contains(e.id) ? -1 : 0);
    final scored = [
      for (final e in pool)
        if (e.mainMuscles.contains(muscle) && !onDay.contains(e.id))
          (e, score(e)),
    ];
    if (scored.isEmpty) return null;
    final best = scored.map((s) => s.$2).reduce(math.max);
    // The pool is by popularity: the best few of the best score.
    final top = [
      for (final (e, s) in scored)
        if (s == best) e,
    ].take(3).toList();
    return top[_random.nextInt(top.length)];
  }

  ProgramItem _item(Exercise exercise) {
    final type = exercise.loggingType;
    final compound = exercise.mechanic == Mechanic.compound;
    // Heavy, low reps need a load to make them heavy.
    final goal = answers.goal == Goal.getStronger && !type.logsWeight
        ? Goal.buildMuscle
        : answers.goal;
    final (repMin, repMax) = switch (goal) {
      Goal.getStronger => compound ? (4, 6) : (8, 12),
      Goal.buildMuscle => compound ? (6, 10) : (10, 15),
      Goal.loseFat => compound ? (10, 15) : (12, 15),
      Goal.generalFitness => compound ? (8, 12) : (10, 15),
    };
    final rest = exercise.defaultRestS ?? fallbackRestS;
    final timed = type.isDurationBased;
    return ProgramItem(
      exerciseId: exercise.id,
      sets: _startSets,
      repMin: timed ? null : repMin,
      repMax: timed ? null : repMax,
      durationS: timed
          ? switch (answers.level) {
              Level.beginner => 30,
              Level.intermediate => 40,
              Level.advanced => 45,
            }
          : null,
      // Shorter rests keep a fat-loss session dense.
      restS: (answers.goal == Goal.loseFat ? math.min(rest, 60) : rest).clamp(
        0,
        ProgramLimits.maxRestS,
      ),
    );
  }

  /// Takes sets, then exercises, off each day until it fits the session:
  /// sets first from the exercise whose muscles are furthest above their
  /// targets, exercises from the end, where the least important are.
  void fitSessions(List<_Day> week) {
    for (final day in week) {
      while (day.estimate > _budget) {
        final volume = _volume(week);
        final trimmable = day.picks.where((p) => p.sets > _minSets);
        if (trimmable.isNotEmpty) {
          // On a tie the later, less important exercise.
          trimmable
              .reduce(
                (a, b) => _surplus(b, volume) >= _surplus(a, volume) ? b : a,
              )
              .sets--;
        } else if (day.picks.length > 1) {
          day.picks.removeLast();
        } else {
          break;
        }
      }
    }
  }

  /// Adds sets to the muscles furthest below their targets, while the
  /// sessions have room and no main muscle passes [maxWeeklySets].
  void raiseToTargets(List<_Day> week) {
    while (true) {
      final volume = _volume(week);
      final needy =
          targets.keys.where((m) => (volume[m] ?? 0) < targets[m]!).toList()
            ..sort(
              (a, b) => (targets[b]! - (volume[b] ?? 0)).compareTo(
                targets[a]! - (volume[a] ?? 0),
              ),
            );
      _Pick? chosen;
      for (final muscle in needy) {
        for (final day in week) {
          for (final pick in day.picks) {
            if (!pick.exercise.mainMuscles.contains(muscle) ||
                pick.sets >= _maxSets ||
                pick.exercise.mainMuscles.any(
                  (m) => (volume[m] ?? 0) + 1 > maxWeeklySets,
                )) {
              continue;
            }
            pick.sets++;
            final fits = day.estimate <= _budget;
            pick.sets--;
            if (fits && (chosen == null || pick.sets < chosen.sets)) {
              chosen = pick;
            }
          }
        }
        if (chosen != null) break;
      }
      if (chosen == null) return;
      chosen.sets++;
    }
  }

  /// Takes sets off muscles more than two above their targets, without
  /// taking another main muscle of the exercise below its own, and off any
  /// muscle above [maxWeeklySets], from the exercise that hurts the other
  /// muscles least.
  void lowerToTargets(List<_Day> week) {
    while (true) {
      final volume = _volume(week);
      bool hurts(_Pick pick) => pick.exercise.mainMuscles.any(
        (m) => targets.containsKey(m) && (volume[m] ?? 0) - 1 < targets[m]!,
      );
      // Fewer sets of a compound exercise last: a tie goes to the later one.
      (bool, int, bool) keep(_Pick pick) => (
        !hurts(pick),
        pick.sets,
        pick.exercise.mechanic != Mechanic.compound,
      );
      _Pick? chosen;
      var dropped = false;
      for (final muscle in targets.keys) {
        final sets = volume[muscle] ?? 0;
        final capped = sets > maxWeeklySets;
        if (!capped && sets <= targets[muscle]! + 2) continue;
        for (final day in week) {
          for (final pick in day.picks) {
            if (!pick.exercise.mainMuscles.contains(muscle) ||
                pick.sets <= _minSets ||
                (!capped && hurts(pick))) {
              continue;
            }
            if (chosen == null || !_before(keep(chosen), keep(pick))) {
              chosen = pick;
            }
          }
        }
        if (chosen != null) break;
        // Every exercise is down to its fewest sets: one goes, from a day
        // that keeps another.
        if (capped && _dropOne(week, muscle, hurts)) {
          dropped = true;
          break;
        }
      }
      if (chosen != null) {
        chosen.sets--;
      } else if (!dropped) {
        return;
      }
    }
  }

  /// Removes the exercise working [muscle] that [hurts] the others least,
  /// the latest on a tie; false when every day would be left empty.
  bool _dropOne(List<_Day> week, Muscle muscle, bool Function(_Pick) hurts) {
    (_Day, _Pick)? dropped;
    for (final day in week) {
      if (day.picks.length < 2) continue;
      for (final pick in day.picks) {
        if (!pick.exercise.mainMuscles.contains(muscle)) continue;
        if (dropped == null || !hurts(pick) || hurts(dropped.$2)) {
          dropped = (day, pick);
        }
      }
    }
    if (dropped == null) return false;
    dropped.$1.picks.remove(dropped.$2);
    return true;
  }

  /// Whether [a] ranks strictly before [b], field by field, true first and
  /// larger first.
  static bool _before((bool, int, bool) a, (bool, int, bool) b) {
    if (a.$1 != b.$1) return a.$1;
    if (a.$2 != b.$2) return a.$2 > b.$2;
    return a.$3 && !b.$3;
  }

  /// How far the targeted main muscles of [pick] are above their targets,
  /// the least of them; untargeted ones count as far above.
  double _surplus(_Pick pick, Map<Muscle, double> volume) {
    var surplus = double.infinity;
    for (final muscle in pick.exercise.mainMuscles) {
      final target = targets[muscle];
      if (target == null) continue;
      surplus = math.min(surplus, (volume[muscle] ?? 0) - target);
    }
    return surplus;
  }
}

Map<Muscle, double> _volume(List<_Day> week) {
  final volume = <Muscle, double>{};
  for (final day in week) {
    for (final pick in day.picks) {
      for (final muscle in pick.exercise.mainMuscles) {
        volume[muscle] = (volume[muscle] ?? 0) + pick.sets;
      }
      for (final muscle in pick.exercise.secondaryMuscles) {
        volume[muscle] = (volume[muscle] ?? 0) + pick.sets * 0.5;
      }
    }
  }
  return volume;
}
