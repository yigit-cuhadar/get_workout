import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/presentation/workout_set_row.dart';

void main() {
  const lb = WeightUnit.lb;

  String? weightCell(String text, double? kg) => numberCellText(
    text,
    value: kg == null ? null : lb.shownFromKg(kg),
    stored: kg,
    toStored: lb.toKg,
  );

  test('text the user typed is kept while it is what is stored', () {
    expect(weightCell('176.375', lb.toKg(176.375)), isNull);
    expect(weightCell('17', lb.toKg(17)), isNull);
    expect(weightCell('', null), isNull);
  });

  test('a shown number retyped over its stored kg is kept', () {
    expect(weightCell('176', 80), isNull);
  });

  test('another stored weight replaces it, even one shown the same', () {
    // The row's set was removed and the next one, 80 kg, moved in.
    expect(weightCell('176.375', 80), '176');
    expect(weightCell('176', lb.toKg(17)), '17');
    expect(weightCell('176', null), '');
    expect(weightCell('', 80), '176');
  });

  test('plain number cells compare the number itself', () {
    expect(numberCellText('8', value: 8, stored: 8), isNull);
    expect(numberCellText('8', value: 10, stored: 10), '10');
  });
}
