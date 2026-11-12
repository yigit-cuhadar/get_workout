import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_stats.dart';
import 'package:get_workout/features/body/domain/body_validation.dart';
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

  test('photo paths match the storage layout', () {
    expect(
      photoPath('u1', 'e1', PhotoPose.left),
      'users/u1/photos/e1/left.jpg',
    );
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

    test('tells whether weights lie before the range', () {
      expect(
        hasWeightBefore(entries, range: StrengthRange.weeks12, now: now),
        isTrue,
      );
      expect(
        hasWeightBefore(entries, range: StrengthRange.all, now: now),
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

  test('a comparison orders by date and pairs what either has', () {
    final later = entry(
      'b',
      DateTime(2026, 11, 1),
      kg: 80,
      measurements: {BodyMeasurement.waist: 84, BodyMeasurement.neck: 38},
      photos: {PhotoPose.back: 'b/back'},
    );
    final earlier = entry(
      'a',
      DateTime(2026, 10, 1),
      kg: 82.5,
      measurements: {BodyMeasurement.waist: 88},
      photos: {PhotoPose.front: 'a/front'},
    );

    final comparison = BodyComparison.of(later, earlier);

    expect(comparison.before, earlier);
    expect(comparison.weightKg.change, -2.5);
    expect(comparison.measurements, {
      BodyMeasurement.neck: (before: null, after: 38.0),
      BodyMeasurement.waist: (before: 88.0, after: 84.0),
    });
    expect(comparison.measurements[BodyMeasurement.neck]!.change, isNull);
    expect(comparison.poses, [PhotoPose.front, PhotoPose.back]);
  });
}
