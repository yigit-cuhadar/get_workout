import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calculators/domain/calories.dart';
import 'package:get_workout/features/calculators/presentation/calculator_format.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/l10n/app_localizations_en.dart';

void main() {
  CalculatorFormat format(WeightUnit unit) => CalculatorFormat(
    AppLocalizationsEn(),
    weightUnit: unit,
    lengthUnit: LengthUnit.cm,
  );

  test('weekly rates are not rounded: 0.5 and 0.25 kg', () {
    final kg = format(WeightUnit.kg);
    final change = weeklyChangeKg(WeightUnit.kg);

    expect(kg.weeklyRate(change.lose), '0.5 kg');
    expect(kg.weeklyRate(change.gain), '0.25 kg');
  });

  test('weekly rates in pounds: 1 and 0.5 lb', () {
    final lb = format(WeightUnit.lb);
    final change = weeklyChangeKg(WeightUnit.lb);

    expect(lb.weeklyRate(change.lose), '1 lb');
    expect(lb.weeklyRate(change.gain), '0.5 lb');
  });
}
