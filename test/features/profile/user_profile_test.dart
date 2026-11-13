import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';

void main() {
  group('limits', () {
    test('days per week are 2 to 6', () {
      expect(ProfileLimits.daysPerWeek(1), isFalse);
      expect(ProfileLimits.daysPerWeek(2), isTrue);
      expect(ProfileLimits.daysPerWeek(6), isTrue);
      expect(ProfileLimits.daysPerWeek(7), isFalse);
    });

    test('the birth year gives an age of 13 to 100', () {
      bool valid(int year) => ProfileLimits.birthYear(year, currentYear: 2026);
      expect(valid(2014), isFalse);
      expect(valid(2013), isTrue);
      expect(valid(1926), isTrue);
      expect(valid(1925), isFalse);
    });

    test('height is 100 to 250 cm', () {
      expect(ProfileLimits.heightCm(99.9), isFalse);
      expect(ProfileLimits.heightCm(100), isTrue);
      expect(ProfileLimits.heightCm(250), isTrue);
      expect(ProfileLimits.heightCm(250.1), isFalse);
    });

    test('weight is 30 to 300 kg', () {
      expect(ProfileLimits.weightKg(29.9), isFalse);
      expect(ProfileLimits.weightKg(30), isTrue);
      expect(ProfileLimits.weightKg(300), isTrue);
      expect(ProfileLimits.weightKg(300.1), isFalse);
    });
  });

  group('UserProfile', () {
    const profile = UserProfile(
      goal: Goal.loseFat,
      heightCm: 180,
      targetWeightKg: 70,
    );

    test('nothing is answered until given', () {
      for (final field in ProfileField.values) {
        expect(const UserProfile().answered(field), isFalse, reason: '$field');
      }
      expect(const UserProfile().onboardingCompleted, isFalse);
    });

    test('without unanswers only that field', () {
      expect(
        profile.without(ProfileField.targetWeight),
        const UserProfile(goal: Goal.loseFat, heightCm: 180),
      );
    });

    test('bodyweight is never part of the equipment', () {
      final answered = profile.copyWith(
        equipment: {Equipment.bodyweight, Equipment.dumbbell},
      );
      expect(answered.equipment, {Equipment.dumbbell});
    });
  });
}
