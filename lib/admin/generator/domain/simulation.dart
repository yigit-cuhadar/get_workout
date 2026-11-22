import 'dart:math' as math;

import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../../features/generator/domain/generated_program.dart';
import '../../../features/generator/domain/generator_answers.dart';
import '../../../features/programs/domain/program.dart';
import '../../../features/programs/domain/program_editing.dart';
import 'generator_rules.dart';

/// A simulator run: a program for [answers] and [seed], from [rules] (an
/// admin's unpublished rules) or, when null, from the published ones.
class SimulationRequest extends Equatable {
  const SimulationRequest({
    required this.answers,
    required this.seed,
    this.rules,
  });

  final GeneratorAnswers answers;
  final int seed;
  final GeneratorRules? rules;

  @override
  List<Object?> get props => [answers, seed, rules];
}

/// How a program item got its exercise (`functions/src/generator/engine.ts`,
/// `Why.source`).
enum PickSource {
  /// Kept by the user on Regenerate.
  kept,

  /// Shared with an earlier slot of the same key.
  key,

  /// Focus work added to the template.
  extra,
  slot,
}

/// A candidate for a slot that was not picked, with its score.
typedef Candidate = ({String exerciseId, double score});

/// Why an item is in the program: the slot it fills, how it was picked
/// and, when scored, the parts of its score and the next candidates.
class PickReason extends Equatable {
  const PickReason({
    required this.exerciseId,
    required this.role,
    required this.priority,
    required this.source,
    this.score = const {},
    this.others = const [],
  });

  final String exerciseId;
  final SlotRole role;
  final int priority;
  final PickSource source;

  /// Score part (`tier`, `equipment`, …) → its value, in the server's order;
  /// empty when the exercise was not scored (kept or shared by key).
  final Map<String, double> score;
  final List<Candidate> others;

  /// The score, the sum of its parts; null when not scored.
  double? get total =>
      score.isEmpty ? null : score.values.fold<double>(0, (a, b) => a + b);

  @override
  List<Object?> get props => [
    exerciseId,
    role,
    priority,
    source,
    score,
    others,
  ];
}

/// What a simulator run gave: the program and why each item was picked.
class Simulation extends Equatable {
  const Simulation({
    required this.program,
    required this.template,
    required this.weeklySets,
    required this.rulesVersion,
    required this.trace,
  });

  final GeneratedProgram program;

  /// The id of the template used.
  final String template;

  /// Sets a week per muscle, 1 per set for a main and 0.5 for a secondary
  /// muscle.
  final Map<Muscle, double> weeklySets;

  /// 0 for unpublished rules.
  final int rulesVersion;

  /// Per day, in the day's item order.
  final List<List<PickReason>> trace;

  @override
  List<Object?> get props => [
    program,
    template,
    weeklySets,
    rulesVersion,
    trace,
  ];
}

/// The weekly target of each of [targeted] for [answers] under [rules], as
/// the engine sets it: the level's target, plus the focus's extra sets for
/// a muscle of a focus area.
Map<Muscle, double> weeklyTargets(
  GeneratorRules rules,
  GeneratorAnswers answers,
  Iterable<Muscle> targeted,
) {
  final extraSets = rules.at(['focus', 'extraSets']);
  final focusMuscles = {
    for (final area in answers.focus)
      for (final code
          in rules.at(['focus', 'areas', area.code]) as List? ?? const [])
        '$code',
  };
  return {
    for (final muscle in targeted)
      muscle:
          switch (rules.at([
            'volume',
            'targets',
            answers.level.code,
            muscle.code,
          ])) {
            final num target => target.toDouble(),
            _ => 0.0,
          } +
          (focusMuscles.contains(muscle.code) && extraSets is num
              ? extraSets.toDouble()
              : 0),
  };
}

/// [day]'s length in whole minutes (at least 1) as the engine counts it
/// against the session: the app's [estimateDay] plus [rules]'
/// `time.setupS` for each exercise.
int dayMinutes(ProgramDay day, GeneratorRules rules) {
  final setupS = switch (rules.at(['time', 'setupS'])) {
    final num seconds => seconds.toInt(),
    _ => 0,
  };
  final seconds = estimateDay(day).inSeconds + setupS * day.items.length;
  return math.max(1, (seconds / 60).round());
}
