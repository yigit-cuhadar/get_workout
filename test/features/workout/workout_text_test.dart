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

    test('derived weights keep their own formatting', () {
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
