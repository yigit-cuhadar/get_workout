import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/presentation/program_text.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/effort.dart';
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

  group('a stored workout\'s set table', () {
    const kg = WeightUnit.kg;

    test('has the columns of the exercise\'s logging type', () {
      expect(l10n.setColumns(LoggingType.weightReps, kg), [
        'Set',
        'kg',
        'Reps',
        'Effort',
      ]);
      expect(l10n.setColumns(LoggingType.assistedBodyweight, WeightUnit.lb), [
        'Set',
        '−lb',
        'Reps',
        'Effort',
      ]);
      expect(l10n.setColumns(LoggingType.duration, kg), [
        'Set',
        'Time',
        'Effort',
      ]);
      expect(l10n.setColumns(LoggingType.weightDuration, kg), [
        'Set',
        'kg',
        'Time',
        'Effort',
      ]);
    });

    test('every row, a drop row too, fills every column', () {
      for (final type in LoggingType.values) {
        final columns = l10n.setColumns(type, kg).length;
        expect(
          l10n.setValues(const WorkoutSet(), type, kg).length + 2,
          columns,
        );
        // Drop rows are built from a set of the drop's weight and reps.
        expect(
          l10n
                  .setValues(const WorkoutSet(weightKg: 20, reps: 6), type, kg)
                  .length +
              2,
          columns,
        );
      }
    });

    test('fills one value per column, leaving out a missing weight', () {
      expect(l10n.setValues(lift(60, 8), LoggingType.weightReps, kg), [
        '60',
        '8',
      ]);
      expect(l10n.setValues(lift(0, 8), LoggingType.weightedBodyweight, kg), [
        '',
        '8',
      ]);
      expect(
        l10n.setValues(
          const WorkoutSet(weightKg: 20, durationS: 45),
          LoggingType.weightDuration,
          kg,
        ),
        ['20', '45 s'],
      );
      expect(l10n.setValues(const WorkoutSet(), LoggingType.duration, kg), [
        '',
      ]);
    });

    test('ends with the effort on the chosen scale and the note', () {
      const set = WorkoutSet(rir: 0, note: 'last rep slow');
      expect(l10n.setRemark(set, EffortScale.byFeel), 'Max · last rep slow');
      expect(l10n.setRemark(set, EffortScale.rpe), 'RPE 10 · last rep slow');
      expect(
        l10n.setRemark(const WorkoutSet(note: 'grip'), EffortScale.rir),
        'grip',
      );
      expect(l10n.setRemark(const WorkoutSet(), EffortScale.rir), '');
    });
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

    test('the set to do now names its kind and counts its own kind', () {
      expect(l10n.setToDo(bench, 3), 'Bench Press · set 3 of 3');
      expect(l10n.setToDo(bench, 2), 'Bench Press · Drop set 2 of 3');
      expect(l10n.setToDo(bench, 0), 'Bench Press · Warm-up');
      final warmed = bench.copyWith(
        sets: [
          lift(20, 8, type: SetType.warmup),
          ...bench.sets,
        ],
      );
      expect(l10n.setToDo(warmed, 1), 'Bench Press · Warm-up 2 of 2');
    });

    test('the effort question and row name the set', () {
      final w = workout('w', [
        bench,
        exercise('Squat', [lift(100, 5)]),
      ]);
      const selected = (exercise: 0, set: 3);
      expect(
        l10n.effortAskTitle(EffortScale.byFeel, bench, 1),
        'How hard was set 1?',
      );
      expect(
        l10n.effortAskTitle(EffortScale.rpe, bench, 2),
        'RPE of drop set 2?',
      );
      expect(
        l10n.effortAskTitle(EffortScale.rir, bench, 1),
        'Reps left in set 1?',
      );
      expect(
        l10n.effortAskValues(w, (exercise: 0, set: 1), selected, WeightUnit.kg),
        '80 kg × 8',
      );
      expect(
        l10n.effortAskValues(w, (exercise: 1, set: 0), selected, WeightUnit.kg),
        'Squat · 100 kg × 5',
      );
      expect(
        l10n.effortRowQuestion(EffortScale.rir, bench, 1),
        'Set 1 · how many more reps could you have done?',
      );
    });

    test('progress counts working sets only', () {
      expect(l10n.exerciseProgress(bench), 'Bench Press · 2/3');
    });

    test('after a rest the next set is named as the set to do', () {
      expect(l10n.restNextText(bench, 0), 'Next: Bench Press · Warm-up');
      expect(
        l10n.restNextText(bench, 2),
        'Next: Bench Press · Drop set 2 of 3',
      );
    });
  });

  test('each effort step says what it means on its scale', () {
    expect(
      [
        for (final step in EffortScale.rir.steps)
          l10n.effortStepMeaning(step, EffortScale.rir),
      ],
      [
        '5 or more reps left',
        '4 reps left',
        '3 reps left',
        '2 reps left',
        '1 rep left',
        'No reps left',
        'Could not finish the last rep',
      ],
    );
    expect(
      [
        for (final step in EffortScale.byFeel.steps)
          l10n.effortStepMeaning(step, EffortScale.byFeel),
      ],
      [
        '4 or more reps left',
        '2–3 reps left',
        '1 rep left',
        'No reps left',
        'Could not finish the last rep',
      ],
    );
  });

  test('RPE goes from 6 or less to 10, each with the reps left', () {
    const rpe = EffortScale.rpe;
    expect(
      [
        for (final step in rpe.steps)
          (l10n.effortStepLabel(step, rpe), l10n.effortStepMeaning(step, rpe)),
      ],
      [
        ('RPE 6 or less', '4 or more reps left'),
        ('RPE 7', '3 reps left'),
        ('RPE 8', '2 reps left'),
        ('RPE 9', '1 rep left'),
        ('RPE 10', 'No reps left'),
        ('Failed', 'Could not finish the last rep'),
      ],
    );
    // An older set with 5 left reads as the easiest step.
    expect(l10n.effortText(const WorkoutSet(rir: 5), rpe), 'RPE 6 or less');
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
        'Heaviest weight 176 lb',
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
        'Best estimated 1RM 225 lb',
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
        'Best set volume 176.4 lb',
      );
      expect(l10n.weightText(kg80, lb), '176.4 lb');
    });
  });
}
