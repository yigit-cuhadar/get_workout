import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/entry_body_fat.dart';
import 'package:get_workout/features/calculators/domain/body_fat.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';

void main() {
  const neck = BodyMeasurement.neck;
  const waist = BodyMeasurement.waist;
  const abdomen = BodyMeasurement.abdomen;
  const hips = BodyMeasurement.hips;

  group('entryBodyFat', () {
    test('a man is estimated from the neck and the abdomen', () {
      final result = entryBodyFat(
        const {neck: 38, abdomen: 85, waist: 70},
        sex: Sex.male,
        heightCm: 180,
      );

      final expected = estimateBodyFat(
        sex: Sex.male,
        heightCm: 180,
        neckCm: 38,
        waistCm: 85,
      );
      expect(result, BodyFatPercent((expected as Calculated<double>).value));
      expect(result.percent, closeTo(16.1, 0.1));
    });

    test('a woman is estimated from the neck, waist and hips', () {
      final result = entryBodyFat(
        const {neck: 32, waist: 70, hips: 98, abdomen: 120},
        sex: Sex.female,
        heightCm: 165,
      );

      final expected = estimateBodyFat(
        sex: Sex.female,
        heightCm: 165,
        neckCm: 32,
        waistCm: 70,
        hipCm: 98,
      );
      expect(result.percent, (expected as Calculated<double>).value);
    });

    test('says what is missing, the profile first', () {
      expect(
        entryBodyFat(const {}, sex: null, heightCm: 180),
        const BodyFatNeedsSex(),
      );
      expect(
        entryBodyFat(const {}, sex: Sex.male, heightCm: null),
        const BodyFatNeedsHeight(),
      );
      expect(
        entryBodyFat(const {waist: 80}, sex: Sex.male, heightCm: 180),
        const BodyFatNeedsMeasurements({neck, abdomen}),
      );
      expect(
        entryBodyFat(
          const {neck: 32, waist: 70},
          sex: Sex.female,
          heightCm: 165,
        ),
        const BodyFatNeedsMeasurements({hips}),
      );
      expect(entryBodyFat(const {}, sex: null, heightCm: 180).percent, isNull);
    });

    test('values the formula rejects give no percentage', () {
      // A neck below the formula's range.
      expect(
        entryBodyFat(
          const {neck: 15, abdomen: 85},
          sex: Sex.male,
          heightCm: 180,
        ),
        const BodyFatOutOfRange(),
      );
      // A neck wider than the abdomen: no positive girth.
      expect(
        entryBodyFat(
          const {neck: 60, abdomen: 50},
          sex: Sex.male,
          heightCm: 180,
        ),
        const BodyFatOutOfRange(),
      );
    });
  });

  group('tracked measurements', () {
    test('the default adds what body fat needs once the sex is known', () {
      expect(defaultTrackedMeasurements(null), BodyMeasurement.standard);
      expect(defaultTrackedMeasurements(Sex.male), {
        ...BodyMeasurement.standard,
        neck,
        abdomen,
      });
      expect(defaultTrackedMeasurements(Sex.female), {
        ...BodyMeasurement.standard,
        neck,
      });
    });

    test('a chosen set wins over the default', () {
      expect(trackedMeasurements({hips}, Sex.male), {hips});
      expect(trackedMeasurements(const {}, Sex.male), isEmpty);
      expect(trackedMeasurements(null, Sex.female), {
        ...BodyMeasurement.standard,
        neck,
      });
    });

    test('body fat is on exactly while all it needs is tracked', () {
      expect(
        tracksBodyFat({neck, abdomen}, sex: Sex.male, heightCm: 180),
        isTrue,
      );
      expect(tracksBodyFat({neck}, sex: Sex.male, heightCm: 180), isFalse);
      expect(
        tracksBodyFat({neck, waist}, sex: Sex.female, heightCm: 165),
        isFalse,
      );
      expect(tracksBodyFat({neck, abdomen}, sex: null, heightCm: 180), isFalse);
      expect(
        tracksBodyFat({neck, abdomen}, sex: Sex.male, heightCm: null),
        isFalse,
      );
    });

    test('ticking body fat adds its measurements and keeps the rest', () {
      final tracked = withBodyFat({BodyMeasurement.chest, neck}, Sex.female);

      expect(tracked, {BodyMeasurement.chest, neck, waist, hips});
      expect(tracksBodyFat(tracked, sex: Sex.female, heightCm: 165), isTrue);
    });

    test('unticking body fat drops only what is not standard', () {
      final man = withBodyFat(BodyMeasurement.standard, Sex.male);
      expect(withoutBodyFat(man, Sex.male), BodyMeasurement.standard);

      final woman = withBodyFat(BodyMeasurement.standard, Sex.female);
      final off = withoutBodyFat(woman, Sex.female);
      expect(off, BodyMeasurement.standard);
      expect(tracksBodyFat(off, sex: Sex.female, heightCm: 165), isFalse);

      // Kept: a man's waist and hips are not his body-fat measurements.
      expect(withoutBodyFat({neck, abdomen, waist, hips}, Sex.male), {
        waist,
        hips,
      });
    });

    test('unticking body fat changes nothing when none of its measurements '
        'is tracked only for it', () {
      final tracked = {waist, hips, BodyMeasurement.chest};
      expect(withoutBodyFat(tracked, Sex.female), tracked);
    });
  });

  test('the formula\'s waist is the abdomen for men, the waist for women, '
      'and both formulas use it', () {
    expect(navyWaist(Sex.male), abdomen);
    expect(navyWaist(Sex.female), waist);
    for (final sex in Sex.values) {
      expect(bodyFatMeasurements(sex), contains(navyWaist(sex)));
    }
    expect(bodyFatMeasurements(Sex.male), {neck, abdomen});
    expect(bodyFatMeasurements(Sex.female), {neck, waist, hips});
  });

  test('pairedMeasurements groups both sides of a pair, in order', () {
    expect(
      pairedMeasurements({
        BodyMeasurement.rightCalf,
        BodyMeasurement.rightThigh,
        BodyMeasurement.leftThigh,
        BodyMeasurement.leftUpperArm,
        waist,
      }),
      [
        [waist],
        [BodyMeasurement.leftUpperArm],
        [BodyMeasurement.leftThigh, BodyMeasurement.rightThigh],
        [BodyMeasurement.rightCalf],
      ],
    );
  });
}
