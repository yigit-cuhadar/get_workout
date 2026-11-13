import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/presentation/program_text.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/presentation/workout_text.dart';
import 'package:get_workout/l10n/app_localizations.dart';

import 'fixtures.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('durations under a minute do not read as 0 min', () {
    expect(l10n.durationMinutes(const Duration(seconds: 24)), '< 1 min');
    expect(l10n.durationMinutes(const Duration(seconds: 89)), '1 min');
    expect(l10n.durationMinutes(const Duration(minutes: 52)), '52 min');
  });

  test('225 lb typed and stored in kg shows 225 again', () {
    final kg = WeightUnit.lb.toKg(225);
    expect(l10n.weightField(kg, WeightUnit.lb), '225');
    expect(l10n.weightField(WeightUnit.lb.toKg(102.5), WeightUnit.lb), '102.5');
  });

  test('last time keeps what a bodyweight exercise\'s weight means', () {
    const kg = WeightUnit.kg;
    final set = lift(20, 8);
    expect(l10n.setWithUnitText(set, LoggingType.weightReps, kg), '20 kg × 8');
    expect(
      l10n.setWithUnitText(set, LoggingType.weightedBodyweight, kg),
      '+20 kg × 8',
    );
    expect(
      l10n.setWithUnitText(set, LoggingType.assistedBodyweight, kg),
      '−20 kg × 8',
    );
    expect(
      l10n.setWithUnitText(lift(0, 8), LoggingType.weightedBodyweight, kg),
      '8',
    );
  });

  test('effort shows on the chosen scale, failed on every one', () {
    const hard = WorkoutSet(rir: 1);
    expect(l10n.effortText(hard, EffortScale.byFeel), 'Hard');
    expect(l10n.effortText(hard, EffortScale.rir), 'RIR 1');
    expect(l10n.effortText(hard, EffortScale.rpe), 'RPE 9');
    const failed = WorkoutSet(rir: 2, toFailure: true);
    for (final scale in EffortScale.values) {
      expect(l10n.effortText(failed, scale), 'Failed');
    }
    expect(l10n.effortText(const WorkoutSet(), EffortScale.rir), isNull);
  });

  group('sets as the set column numbers them', () {
    final bench = exercise('Bench Press', [
      lift(40, 10, type: SetType.warmup),
      lift(80, 8),
      lift(80, 8, type: SetType.drop),
      lift(80, 8, done: false),
    ]);

    test('labels count working sets and mark warm-ups and drops', () {
      expect(
        [for (var i = 0; i < 4; i++) l10n.setLabel(bench, i)],
        ['W', '1', '2D', '3'],
      );
    });

    test('the set to do now counts working sets only', () {
      expect(l10n.setToDo(bench, 3), 'Bench Press · set 3 of 3');
      expect(l10n.setToDo(bench, 0), 'Bench Press · set W');
    });
  });

  group('a weight typed in the other unit shows rounded', () {
    const lb = WeightUnit.lb;
    final kg80 = WeightUnit.kg.toKg(80);

    test('in fields, sets, targets and records', () {
      expect(l10n.weightField(kg80, lb), '176');
      expect(
        l10n.setText(
          WorkoutSet(weightKg: kg80, reps: 8),
          LoggingType.weightReps,
          lb,
        ),
        '176 × 8',
      );
      expect(
        l10n.itemSummary(
          ProgramItem(
            exerciseId: 'e',
            sets: 3,
            repMin: 8,
            restS: 90,
            targetKg: lb.toKg(45),
          ),
          WeightUnit.kg,
        ),
        '3 × 8 · 20.5 kg',
      );
      expect(
        l10n.recordText(
          NewRecord(
            exerciseId: 'e',
            name: 'Squat',
            kind: RecordKind.heaviestWeight,
            value: kg80,
          ),
          lb,
        ),
        'Squat: Heaviest weight 176 lb',
      );
    });

    test('but one typed in the shown unit keeps its decimals', () {
      expect(l10n.weightField(lb.toKg(12.25), lb), '12.25');
      expect(l10n.liftedWeightText(lb.toKg(12.25), lb), '12.25 lb');
    });

    test('a positive weight never reads as 0', () {
      expect(
        l10n.setText(
          const WorkoutSet(weightKg: 0.2, reps: 8),
          LoggingType.weightReps,
          lb,
        ),
        '0.44 × 8',
      );
      expect(l10n.liftedWeightText(lb.toKg(0.5), WeightUnit.kg), '0.23 kg');
    });

    test('an estimated one-rep max is always rounded', () {
      expect(
        l10n.recordText(
          NewRecord(
            exerciseId: 'e',
            name: 'Squat',
            kind: RecordKind.bestE1rm,
            value: lb.toKg(225.4),
          ),
          lb,
        ),
        'Squat: Best estimated 1RM 225 lb',
      );
      expect(l10n.estimatedWeightText(102.3, WeightUnit.kg), '102.5 kg');
    });

    test('volume keeps its own formatting', () {
      expect(
        l10n.recordText(
          NewRecord(
            exerciseId: 'e',
            name: 'Squat',
            kind: RecordKind.bestSetVolume,
            value: kg80,
          ),
          lb,
        ),
        'Squat: Best set volume 176.4 lb',
      );
      expect(l10n.weightText(kg80, lb), '176.4 lb');
    });
  });
}
