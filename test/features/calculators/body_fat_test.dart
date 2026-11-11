import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calculators/domain/body_fat.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';
import 'package:get_workout/features/calculators/domain/calories.dart';

void main() {
  test('male reference value', () {
    // log10(85 − 38) = 1.672098, log10(180) = 2.255273;
    // 1.0324 − 0.19077·1.672098 + 0.15456·2.255273 = 1.061989;
    // 495 / 1.061989 − 450 = 16.11.
    final result = estimateBodyFat(
      sex: Sex.male,
      heightCm: 180,
      neckCm: 38,
      waistCm: 85,
    );
    expect((result as Calculated<double>).value, closeTo(16.11, 0.01));
  });

  test('female reference value', () {
    // log10(70 + 95 − 33) = 2.120574, log10(165) = 2.217484;
    // 1.29579 − 0.35004·2.120574 + 0.22100·2.217484 = 1.043568;
    // 495 / 1.043568 − 450 = 24.33.
    final result = estimateBodyFat(
      sex: Sex.female,
      heightCm: 165,
      neckCm: 33,
      waistCm: 70,
      hipCm: 95,
    );
    expect((result as Calculated<double>).value, closeTo(24.33, 0.01));
  });

  test('the hip is ignored for men', () {
    Calculation<double> male(double? hip) => estimateBodyFat(
      sex: Sex.male,
      heightCm: 180,
      neckCm: 38,
      waistCm: 85,
      hipCm: hip,
    );
    expect(male(100), male(null));
  });

  test('women need a hip measurement', () {
    expect(
      estimateBodyFat(sex: Sex.female, heightCm: 165, neckCm: 33, waistCm: 70),
      const OutOfRange<double>(CalculatorInput.hip, hipRangeCm),
    );
  });

  test('a waist no larger than the neck is a measurement problem', () {
    expect(
      estimateBodyFat(sex: Sex.male, heightCm: 180, neckCm: 45, waistCm: 45),
      const Rejected<double>(CalculatorProblem.checkMeasurements),
    );
  });

  test('a result below 2 % is a measurement problem', () {
    // log10(15) = 1.176091; density 1.160200; 495 / 1.1602 − 450 = −23.4.
    expect(
      estimateBodyFat(sex: Sex.male, heightCm: 190, neckCm: 45, waistCm: 60),
      const Rejected<double>(CalculatorProblem.checkMeasurements),
    );
  });

  test('a result above 60 % is a measurement problem', () {
    // log10(370) = 2.568202, log10(150) = 2.176091;
    // 1.29579 − 0.35004·2.568202 + 0.22100·2.176091 = 0.877732;
    // 495 / 0.877732 − 450 = 113.95.
    expect(
      estimateBodyFat(
        sex: Sex.female,
        heightCm: 150,
        neckCm: 30,
        waistCm: 200,
        hipCm: 200,
      ),
      const Rejected<double>(CalculatorProblem.checkMeasurements),
    );
  });

  test('measurements out of range name the input', () {
    expect(
      estimateBodyFat(sex: Sex.male, heightCm: 180, neckCm: 19, waistCm: 85),
      const OutOfRange<double>(CalculatorInput.neck, neckRangeCm),
    );
    expect(
      estimateBodyFat(sex: Sex.male, heightCm: 180, neckCm: 38, waistCm: 251),
      const OutOfRange<double>(CalculatorInput.waist, waistRangeCm),
    );
    expect(
      estimateBodyFat(sex: Sex.male, heightCm: 90, neckCm: 38, waistCm: 85),
      const OutOfRange<double>(CalculatorInput.height, heightRangeCm),
    );
  });
}
