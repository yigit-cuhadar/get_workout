import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_questions.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

void main() {
  group('displayRange', () {
    test('metric limits are shown as they are', () {
      expect(
        displayRange(
          ProfileLimits.minHeightCm,
          ProfileLimits.maxHeightCm,
          LengthUnit.cm.fromCm,
        ),
        (min: 100.0, max: 250.0),
      );
    });

    test('imperial limits are rounded inwards', () {
      expect(
        displayRange(
          ProfileLimits.minHeightCm,
          ProfileLimits.maxHeightCm,
          LengthUnit.inch.fromCm,
        ),
        (min: 39.4, max: 98.4),
      );
      expect(
        displayRange(
          ProfileLimits.minWeightKg,
          ProfileLimits.maxWeightKg,
          WeightUnit.lb.fromKg,
        ),
        (min: 66.2, max: 661.3),
      );
    });

    test('every shown imperial bound is itself accepted', () {
      final height = displayRange(
        ProfileLimits.minHeightCm,
        ProfileLimits.maxHeightCm,
        LengthUnit.inch.fromCm,
      );
      final weight = displayRange(
        ProfileLimits.minWeightKg,
        ProfileLimits.maxWeightKg,
        WeightUnit.lb.fromKg,
      );
      for (final inches in [height.min, height.max]) {
        expect(ProfileLimits.heightCm(LengthUnit.inch.toCm(inches)), isTrue);
      }
      for (final pounds in [weight.min, weight.max]) {
        expect(ProfileLimits.weightKg(WeightUnit.lb.toKg(pounds)), isTrue);
      }
    });
  });

  group('rulerRange', () {
    test('metric limits are whole steps already', () {
      expect(
        rulerRange(
          ProfileLimits.minHeightCm,
          ProfileLimits.maxHeightCm,
          LengthUnit.cm.fromCm,
          1,
        ),
        (min: 100.0, max: 250.0),
      );
      final weight = rulerRange(
        ProfileLimits.minWeightKg,
        ProfileLimits.maxWeightKg,
        WeightUnit.kg.fromKg,
        0.1,
      );
      expect(weight.min, closeTo(30, 1e-9));
      expect(weight.max, closeTo(300, 1e-9));
    });

    test('imperial limits are rounded inwards to a step, and accepted', () {
      final height = rulerRange(
        ProfileLimits.minHeightCm,
        ProfileLimits.maxHeightCm,
        LengthUnit.inch.fromCm,
        1,
      );
      expect(height, (min: 40.0, max: 98.0));
      final weight = rulerRange(
        ProfileLimits.minWeightKg,
        ProfileLimits.maxWeightKg,
        WeightUnit.lb.fromKg,
        0.1,
      );
      expect(weight.min, closeTo(66.2, 1e-9));
      expect(weight.max, closeTo(661.3, 1e-9));
      for (final inches in [height.min, height.max]) {
        expect(ProfileLimits.heightCm(LengthUnit.inch.toCm(inches)), isTrue);
      }
      for (final pounds in [weight.min, weight.max]) {
        expect(ProfileLimits.weightKg(WeightUnit.lb.toKg(pounds)), isTrue);
      }
    });
  });
}
