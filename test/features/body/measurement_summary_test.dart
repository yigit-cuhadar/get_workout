import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/entry_body_fat.dart';
import 'package:get_workout/features/body/domain/measurement_summary.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';

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

void main() {
  const neck = BodyMeasurement.neck;
  const waist = BodyMeasurement.waist;
  const abdomen = BodyMeasurement.abdomen;
  const leftThigh = BodyMeasurement.leftThigh;
  const rightThigh = BodyMeasurement.rightThigh;
  const leftCalf = BodyMeasurement.leftCalf;
  final now = DateTime.utc(2026, 11, 12);
  const man = UserProfile(sex: Sex.male, heightCm: 180);

  final newest = entry(
    'd3',
    DateTime.utc(2026, 11, 10),
    kg: 80,
    measurements: {waist: 84},
  );
  final log = entry('w', DateTime.utc(2026, 11, 5), kg: 80.5);
  final middle = entry(
    'd2',
    DateTime.utc(2026, 10, 1),
    photos: {PhotoPose.front: 'd2/front'},
  );
  final oldest = entry(
    'd1',
    DateTime.utc(2026, 6, 1),
    kg: 86,
    measurements: {waist: 90},
  );
  final entries = [newest, log, middle, oldest];

  group('baselines', () {
    test('a measurement day has measurements or photos; a weight log '
        'is none', () {
      expect(isMeasurementDay(newest), isTrue);
      expect(isMeasurementDay(middle), isTrue);
      expect(isMeasurementDay(log), isFalse);
    });

    test('the candidates are the earlier measurement days, newest first', () {
      expect(baselineCandidates(entries, newest), [middle, oldest]);
      expect(baselineCandidates(entries, middle), [oldest]);
      expect(baselineCandidates(entries, oldest), isEmpty);
    });

    test('the newest comparable day needs an earlier one', () {
      expect(newestComparable(entries), newest);
      expect(newestComparable([log, oldest]), isNull);
      expect(newestComparable([newest, log]), isNull);
      expect(newestComparable(const []), isNull);
    });

    test('previous, first and a chosen day', () {
      const find = FindBaseline();

      expect(find(entries, newest, const PreviousDay()), middle);
      expect(find(entries, newest, const FirstDay()), oldest);
      expect(find(entries, newest, const ChosenDay('d1')), oldest);
    });

    test('a chosen day that is no candidate gives the previous day', () {
      const find = FindBaseline();

      expect(find(entries, newest, const ChosenDay('gone')), middle);
      expect(find(entries, newest, const ChosenDay('w')), middle);
      expect(find(entries, middle, const ChosenDay('d3')), oldest);
    });

    test('nothing earlier gives no baseline', () {
      const find = FindBaseline();

      expect(find(entries, oldest, const PreviousDay()), isNull);
      expect(find(entries, oldest, const FirstDay()), isNull);
    });
  });

  group('rows', () {
    test('weight and every measurement of either day, pairs on one row', () {
      final summary = MeasurementSummary.of(
        after: entry(
          'b',
          DateTime.utc(2026, 11, 1),
          kg: 80,
          measurements: {waist: 84, leftThigh: 58, rightThigh: 59},
        ),
        before: entry(
          'a',
          DateTime.utc(2026, 10, 1),
          kg: 82.5,
          measurements: {waist: 88, neck: 39, leftThigh: 60, leftCalf: 38},
        ),
        profile: const UserProfile(),
        now: now,
      );

      expect(summary.weightKg, (before: 82.5, after: 80.0));
      expect(summary.weightKg!.change, -2.5);
      expect(summary.measurements, [
        const MeasurementRow([neck], [(before: 39, after: null)]),
        const MeasurementRow([waist], [(before: 88, after: 84)]),
        const MeasurementRow(
          [leftThigh, rightThigh],
          [(before: 60, after: 58), (before: null, after: 59)],
        ),
        const MeasurementRow([leftCalf], [(before: 38, after: null)]),
      ]);
      expect(summary.measurements[0].values.single.change, isNull);
      expect(summary.measurements[1].values.single.change, -4);
    });

    test('no weight on either day gives no weight row', () {
      final summary = MeasurementSummary.of(
        after: middle,
        before: entry('x', DateTime.utc(2026, 9, 1), measurements: {waist: 1}),
        profile: const UserProfile(),
        now: now,
      );

      expect(summary.weightKg, isNull);
    });

    test('a day alone has only its own values', () {
      final summary = MeasurementSummary.of(
        after: newest,
        before: null,
        profile: const UserProfile(),
        now: now,
      );

      expect(summary.before, isNull);
      expect(summary.weightKg, (before: null, after: 80.0));
      expect(summary.measurements, [
        const MeasurementRow([waist], [(before: null, after: 84)]),
      ]);
      expect(summary.weightKg!.change, isNull);
    });

    test('the poses of either day, in order', () {
      final summary = MeasurementSummary.of(
        after: entry('b', now, photos: {PhotoPose.back: 'b/back'}),
        before: entry(
          'a',
          DateTime.utc(2026, 10, 1),
          photos: {PhotoPose.left: 'a/left', PhotoPose.front: 'a/front'},
        ),
        profile: const UserProfile(),
        now: now,
      );

      expect(summary.poses, [PhotoPose.front, PhotoPose.left, PhotoPose.back]);
    });
  });

  group('body composition', () {
    final after = entry(
      'b',
      DateTime.utc(2026, 11, 1),
      kg: 80,
      measurements: {neck: 38, abdomen: 85},
    );
    final afterPercent = entryBodyFat(
      after.measurements,
      sex: Sex.male,
      heightCm: 180,
    ).percent!;

    test('body fat splits each day\'s weight into fat and lean mass', () {
      final before = entry(
        'a',
        DateTime.utc(2026, 10, 1),
        kg: 84,
        measurements: {neck: 38, abdomen: 90},
      );
      final beforePercent = entryBodyFat(
        before.measurements,
        sex: Sex.male,
        heightCm: 180,
      ).percent!;

      final summary = MeasurementSummary.of(
        after: after,
        before: before,
        profile: man,
        now: now,
      );

      expect(summary.bodyFat, BodyFatPercent(afterPercent));
      final composition = summary.composition!;
      expect(composition.percent, (before: beforePercent, after: afterPercent));
      expect(composition.fatKg!.after, closeTo(80 * afterPercent / 100, 1e-9));
      expect(
        composition.fatKg!.before,
        closeTo(84 * beforePercent / 100, 1e-9),
      );
      expect(
        composition.leanKg!.after,
        closeTo(80 - 80 * afterPercent / 100, 1e-9),
      );
      expect(
        composition.leanKg!.change,
        closeTo(
          (80 - 80 * afterPercent / 100) - (84 - 84 * beforePercent / 100),
          1e-9,
        ),
      );
    });

    test('an earlier day without body fat or weight has no earlier '
        'values', () {
      final summary = MeasurementSummary.of(
        after: after,
        before: entry('a', DateTime.utc(2026, 10, 1), kg: 84),
        profile: man,
        now: now,
      );

      final composition = summary.composition!;
      expect(composition.percent.before, isNull);
      expect(composition.fatKg!.before, isNull);
      expect(composition.leanKg!.before, isNull);

      final withoutWeight = MeasurementSummary.of(
        after: after,
        before: entry(
          'a',
          DateTime.utc(2026, 10, 1),
          measurements: {neck: 38, abdomen: 90},
        ),
        profile: man,
        now: now,
      ).composition!;
      expect(withoutWeight.percent.before, isNotNull);
      expect(withoutWeight.fatKg!.before, isNull);
    });

    test('without the day\'s weight there is body fat but no fat or lean '
        'mass', () {
      final summary = MeasurementSummary.of(
        after: entry('b', now, measurements: after.measurements),
        before: null,
        profile: man,
        now: now,
      );

      expect(summary.composition!.percent.after, afterPercent);
      expect(summary.composition!.fatKg, isNull);
      expect(summary.composition!.leanKg, isNull);
    });

    test('says what body fat is missing', () {
      MeasurementSummary summary(UserProfile profile, BodyEntry after) =>
          MeasurementSummary.of(
            after: after,
            before: null,
            profile: profile,
            now: now,
          );

      final noSex = summary(const UserProfile(heightCm: 180), after);
      expect(noSex.composition, isNull);
      expect(noSex.bodyFat, const BodyFatNeedsSex());
      expect(
        summary(const UserProfile(sex: Sex.male), after).bodyFat,
        const BodyFatNeedsHeight(),
      );
      expect(
        summary(man, entry('b', now, measurements: {neck: 38})).bodyFat,
        const BodyFatNeedsMeasurements({abdomen}),
      );
      expect(
        summary(
          man,
          entry('b', now, measurements: {neck: 45, abdomen: 44}),
        ).bodyFat,
        const BodyFatOutOfRange(),
      );
    });
  });

  group('target', () {
    final before = entry('a', DateTime.utc(2026, 10, 1), kg: 84);
    final after = entry('b', DateTime.utc(2026, 10, 29), kg: 82);

    TargetProgress? target(
      double? targetKg, {
      BodyEntry? from,
      BodyEntry? to,
      DateTime? at,
    }) => MeasurementSummary.of(
      after: to ?? after,
      before: from,
      profile: UserProfile(targetWeightKg: targetKg),
      now: at ?? now,
    ).target;

    test('the distance from the day\'s weight, with an estimate at the '
        'rate since the earlier day', () {
      // 2 kg in 28 days, 4 kg to go: 56 more days.
      expect(
        target(78, from: before),
        TargetProgress(
          targetKg: 78,
          toGoKg: -4,
          estimate: DateTime.utc(2026, 12, 24),
        ),
      );
      // Gaining toward a higher target works the same way.
      expect(
        target(
          90,
          from: entry('a', DateTime.utc(2026, 10, 1), kg: 80),
          to: entry('b', DateTime.utc(2026, 10, 29), kg: 82),
        )!.estimate,
        DateTime.utc(2027, 2, 18),
      );
    });

    test('none without a target or a weight on the day', () {
      expect(target(null, from: before), isNull);
      expect(target(78, from: before, to: entry('b', now)), isNull);
    });

    test('reached gives no estimate', () {
      final reached = target(82.04, from: before)!;
      expect(reached.reached, isTrue);
      expect(reached.estimate, isNull);
      expect(target(78, from: before)!.reached, isFalse);
    });

    test('no estimate without an earlier weight', () {
      expect(target(78)!.estimate, isNull);
      expect(target(78)!.toGoKg, -4);
      expect(
        target(78, from: entry('a', DateTime.utc(2026, 10, 1)))!.estimate,
        isNull,
      );
    });

    test('no estimate from entries less than a week apart', () {
      final close = entry('a', DateTime.utc(2026, 10, 23), kg: 84);
      expect(target(78, from: close)!.estimate, isNull);
      final week = entry('a', DateTime.utc(2026, 10, 22), kg: 84);
      expect(target(78, from: week)!.estimate, isNotNull);
    });

    test('no estimate when the weight did not move toward the target', () {
      final same = entry('a', DateTime.utc(2026, 10, 1), kg: 82);
      expect(target(78, from: same)!.estimate, isNull);
      final away = entry('a', DateTime.utc(2026, 10, 1), kg: 81);
      expect(target(78, from: away)!.estimate, isNull);
      expect(target(90, from: before)!.estimate, isNull);
    });

    test('no estimate more than two years out, or already past', () {
      // 0.01 kg in 28 days: centuries.
      final slow = entry('a', DateTime.utc(2026, 10, 1), kg: 82.01);
      expect(target(78, from: slow)!.estimate, isNull);
      // By the rate it was due before now.
      expect(
        target(78, from: before, at: DateTime.utc(2027))!.estimate,
        isNull,
      );
    });
  });
}
