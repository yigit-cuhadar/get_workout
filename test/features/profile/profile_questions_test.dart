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
}
