import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/domain/retyped_weights.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

void main() {
  const lb = WeightUnit.lb;
  late RetypedWeights<int> retyped;

  setUp(() => retyped = RetypedWeights<int>());

  /// Types [steps] one after another into field 0, starting from [kg].
  double? type(double? kg, List<String> steps) {
    var stored = kg;
    for (final text in steps) {
      stored = retyped.kg(0, text, lb, stored);
    }
    return stored;
  }

  test('80 kg shown as 176 lb and retyped as 176 stays 80 kg', () {
    expect(retyped.kg(0, '176', lb, 80), 80);
  });

  test('also when the text gets there through other numbers', () {
    expect(type(80, ['17', '1', '', '1', '17', '176']), 80);
  });

  test('another number is stored as typed', () {
    expect(type(80, ['17', '177']), lb.toKg(177));
    expect(type(80, ['176.4']), lb.toKg(176.4));
  });

  test('blank or unreadable text clears the weight', () {
    expect(retyped.kg(0, '', lb, 80), isNull);
    expect(retyped.kg(0, '.', lb, 80), isNull);
  });

  test('an empty field has nothing to restore', () {
    expect(type(null, ['1', '17', '176']), lb.toKg(176));
  });

  test('fields are apart, and clear forgets them', () {
    retyped.kg(0, '17', lb, 80);
    expect(retyped.kg(1, '176', lb, lb.toKg(17)), lb.toKg(176));
    retyped.clear();
    expect(retyped.kg(0, '176', lb, lb.toKg(17)), lb.toKg(176));
  });
}
