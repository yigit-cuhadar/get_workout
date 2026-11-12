import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
import 'workout.dart';

/// One step of an effort scale: reps in reserve, or failed (the last rep
/// was attempted and not completed). Every scale stores its steps the same
/// way on a set: [rir], and a failed one as `toFailure` with rir 0.
class EffortStep extends Equatable {
  const EffortStep.reserve(this.rir) : failed = false;
  const EffortStep._failed() : rir = 0, failed = true;

  static const failure = EffortStep._failed();

  final int rir;
  final bool failed;

  @override
  List<Object?> get props => [rir, failed];
}

extension EffortScaleSteps on EffortScale {
  /// Easiest first, [EffortStep.failure] last. By feel: easy (4+ left),
  /// moderate (2-3), hard (1), max (0); RIR and RPE: every reps in reserve
  /// from [WorkoutLimits.maxRir] (5+) down to 0.
  List<EffortStep> get steps => [
    ...switch (this) {
      EffortScale.byFeel => const [
        EffortStep.reserve(4),
        EffortStep.reserve(2),
        EffortStep.reserve(1),
        EffortStep.reserve(0),
      ],
      EffortScale.rir || EffortScale.rpe => [
        for (var rir = WorkoutLimits.maxRir; rir >= 0; rir--)
          EffortStep.reserve(rir),
      ],
    },
    EffortStep.failure,
  ];

  /// The step [set] shows as on this scale; null without effort. A set to
  /// failure shows failed whatever its rir, as older sets may have one.
  EffortStep? stepOf(WorkoutSet set) {
    if (set.toFailure) return EffortStep.failure;
    final rir = set.rir;
    if (rir == null) return null;
    return EffortStep.reserve(switch (this) {
      EffortScale.byFeel =>
        rir >= 4
            ? 4
            : rir >= 2
            ? 2
            : rir == 1
            ? 1
            : 0,
      EffortScale.rir || EffortScale.rpe => rir.clamp(0, WorkoutLimits.maxRir),
    });
  }
}

extension SetEffort on WorkoutSet {
  /// This set with [step] as its effort; null clears it.
  WorkoutSet withEffort(EffortStep? step) =>
      copyWith(rir: () => step?.rir, toFailure: step?.failed ?? false);
}
