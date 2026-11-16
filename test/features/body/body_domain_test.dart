import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_stats.dart';
import 'package:get_workout/features/body/domain/body_validation.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/strength/domain/strength.dart';

void main() {
  final now = DateTime(2026, 11, 12, 9);

  BodyEntry entry(
    String id,
    DateTime date, {
    double? kg,
    Map<BodyMeasurement, double> measurements = const {},
    Map<PhotoPose, String> photos = const {},
  }) => BodyEntry(
    id: id,
    date: date,
    weightKg: kg,
    measurements: measurements,
    photos: photos,
  );

  test('photo paths match the storage layout, with a revision', () {
    expect(
      photoPath('u1', 'e1', PhotoPose.left, 1700),
      'users/u1/photos/e1/left-1700.jpg',
    );
    expect(isPhotoOf('users/u1/photos/e1/left-1.jpg', 'u1'), isTrue);
    expect(isPhotoOf('users/u12/photos/e1/left-1.jpg', 'u1'), isFalse);
  });

  group('validation', () {
    test('a weight-only entry in range is valid', () {
      expect(validateBodyEntry(entry('a', now, kg: 80), now: now), isEmpty);
    });

    test('an entry with nothing is empty', () {
      expect(validateBodyEntry(entry('a', now), now: now), {BodyIssue.empty});
    });

    test('a photo alone is enough', () {
      final photo = entry('a', now, photos: {PhotoPose.front: 'p'});
      expect(validateBodyEntry(photo, now: now), isEmpty);
    });

    test('values out of range, NaN and future dates are refused', () {
      final bad = entry(
        'a',
        now.add(const Duration(minutes: 1)),
        kg: double.nan,
        measurements: {BodyMeasurement.waist: 300},
      );
      expect(validateBodyEntry(bad, now: now), {
        BodyIssue.dateInFuture,
        BodyIssue.weightOutOfRange,
        BodyIssue.measurementOutOfRange,
      });
      expect(validateBodyEntry(entry('a', now, kg: 29.9), now: now), {
        BodyIssue.weightOutOfRange,
      });
    });
  });

  test('the limits as shown in lb and inches are accepted, '
      'one shown step beyond them is not', () {
    double lb(double value) => WeightUnit.lb.toKg(value);
    double inch(double value) => LengthUnit.inch.toCm(value);
    expect(BodyLimits.weightKg(lb(66.1)), isTrue);
    expect(BodyLimits.weightKg(lb(661.4)), isTrue);
    expect(BodyLimits.weightKg(lb(66.0)), isFalse);
    expect(BodyLimits.weightKg(lb(661.5)), isFalse);
    expect(BodyLimits.weightKg(29.9), isFalse);
    expect(BodyLimits.measurementCm(inch(3.9)), isTrue);
    expect(BodyLimits.measurementCm(inch(98.4)), isTrue);
    expect(BodyLimits.measurementCm(inch(3.8)), isFalse);
    expect(BodyLimits.measurementCm(inch(98.5)), isFalse);
    expect(BodyLimits.measurementCm(double.nan), isFalse);
  });

  group('weight series', () {
    // Newest first, as the repository gives them.
    final entries = [
      entry('c', DateTime(2026, 11, 10), kg: 80),
      entry(
        'b',
        DateTime(2026, 10, 1),
        measurements: {BodyMeasurement.hips: 90},
      ),
      entry('a', DateTime(2026, 5, 1), kg: 84),
    ];

    test('holds the weights in range, oldest first', () {
      expect(weightSeries(entries, range: StrengthRange.all, now: now), [
        (date: DateTime(2026, 5, 1), kg: 84.0),
        (date: DateTime(2026, 11, 10), kg: 80.0),
      ]);
      expect(weightSeries(entries, range: StrengthRange.weeks12, now: now), [
        (date: DateTime(2026, 11, 10), kg: 80.0),
      ]);
    });

    test('tells whether entries lie before the range', () {
      expect(
        hasEntryBefore(entries, range: StrengthRange.weeks12, now: now),
        isTrue,
      );
      expect(
        hasEntryBefore(
          entries.sublist(0, 2),
          range: StrengthRange.weeks12,
          now: now,
        ),
        isFalse,
      );
      expect(
        hasEntryBefore(entries, range: StrengthRange.all, now: now),
        isFalse,
      );
    });

    test('the latest weight skips entries without one', () {
      expect(latestWeightKg(entries.sublist(1)), 84);
      expect(latestWeightKg(const []), isNull);
    });
  });

  test('previous photos are the newest of each pose before the date', () {
    final entries = [
      entry('d', DateTime(2026, 11, 12), photos: {PhotoPose.front: 'd/front'}),
      entry('c', DateTime(2026, 11, 1), photos: {PhotoPose.front: 'c/front'}),
      entry(
        'b',
        DateTime(2026, 10, 1),
        photos: {PhotoPose.front: 'b/front', PhotoPose.back: 'b/back'},
      ),
    ];
    expect(previousPhotos(entries, date: DateTime(2026, 11, 12)), {
      PhotoPose.front: 'c/front',
      PhotoPose.back: 'b/back',
    });
    expect(
      previousPhotos(entries, date: DateTime(2026, 12, 1), excludeId: 'd'),
      {PhotoPose.front: 'c/front', PhotoPose.back: 'b/back'},
    );
  });

  group('overview boxes', () {
    final oct18 = entry(
      'oct18',
      DateTime(2026, 10, 18),
      kg: 84.1,
      measurements: const {BodyMeasurement.waist: 92},
    );
    final nov1 = entry(
      'nov1',
      DateTime(2026, 11, 1),
      kg: 82.9,
      measurements: const {BodyMeasurement.waist: 88.5},
    );
    final nov13 = entry('nov13', DateTime(2026, 11, 13), kg: 82.4);
    const fat = {'nov1': 19.5, 'oct18': 21.0};

    test('change since the measurement day before the newest one', () {
      final boxes = bodyOverview([nov13, nov1, oct18], fat, targetKg: 78);
      expect(boxes.weight!.value, 82.4);
      expect(boxes.weight!.change, closeTo(-1.7, 1e-9));
      expect(boxes.weight!.tone, ChangeTone.good);
      expect(boxes.bodyFat!.change, closeTo(-1.5, 1e-9));
      expect(boxes.bodyFat!.tone, ChangeTone.good);
      // The latest weight at the newest body fat.
      expect(boxes.leanMass!.value, closeTo(82.4 * 0.805, 1e-9));
      expect(boxes.leanMass!.change, closeTo(-0.107, 1e-9));
      expect(boxes.leanMass!.tone, ChangeTone.bad);
    });

    test('weight away from the target is bad; no target is neutral', () {
      final up = entry('up', DateTime(2026, 11, 14), kg: 85);
      expect(
        bodyOverview([up, nov1, oct18], fat, targetKg: 78).weight!.tone,
        ChangeTone.bad,
      );
      expect(
        bodyOverview([up, nov1, oct18], fat, targetKg: null).weight!.tone,
        ChangeTone.neutral,
      );
    });

    test('one measurement day or none: values without changes', () {
      final one = bodyOverview([nov13, nov1], fat, targetKg: 78);
      expect(one.weight!.change, isNull);
      expect(one.bodyFat!.value, 19.5);
      expect(one.bodyFat!.change, isNull);

      final none = bodyOverview([nov13], const {}, targetKg: 78);
      expect(none.weight!.value, 82.4);
      expect(none.bodyFat, isNull);
      expect(none.leanMass, isNull);
    });
  });
}
