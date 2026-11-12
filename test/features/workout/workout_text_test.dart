import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
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
}
