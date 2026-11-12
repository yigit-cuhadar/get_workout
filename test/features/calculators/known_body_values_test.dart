import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_repository.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/calculators/domain/body_fat.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';
import 'package:get_workout/features/calculators/domain/calculators_usecases.dart';
import 'package:get_workout/features/calculators/domain/calories.dart';
import 'package:get_workout/features/calculators/domain/known_body_values.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:mocktail/mocktail.dart';

class MockProfileRepository extends Mock implements ProfileRepository {}

class MockBodyRepository extends Mock implements BodyRepository {}

BodyEntry entry(
  String id,
  DateTime date, {
  double? weightKg,
  Map<BodyMeasurement, double> measurements = const {},
}) => BodyEntry(
  id: id,
  date: date,
  weightKg: weightKg,
  measurements: measurements,
);

double navy({
  required Sex sex,
  required double heightCm,
  required double neckCm,
  required double waistCm,
  double? hipCm,
}) => (estimateBodyFat(
  sex: sex,
  heightCm: heightCm,
  neckCm: neckCm,
  waistCm: waistCm,
  hipCm: hipCm,
) as Calculated<double>).value;

void main() {
  const man = UserProfile(
    sex: Sex.male,
    birthYear: 1990,
    heightCm: 180,
    weightKg: 82,
    daysPerWeek: 4,
  );

  group('GetKnownBodyValues', () {
    late MockProfileRepository profiles;
    late MockBodyRepository body;
    late GetKnownBodyValues getKnownValues;

    setUp(() {
      profiles = MockProfileRepository();
      body = MockBodyRepository();
      getKnownValues = GetKnownBodyValues(
        WatchProfile(profiles),
        WatchBodyEntries(body),
        clock: () => DateTime(2026, 11, 12),
      );
    });

    void given({
      Stream<UserProfile>? profile,
      Stream<List<BodyEntry>>? entries,
    }) {
      when(() => profiles.watchProfile('u1'))
          .thenAnswer((_) => profile ?? Stream.value(const UserProfile()));
      when(() => body.watchEntries('u1'))
          .thenAnswer((_) => entries ?? Stream.value(const []));
    }

    test('the profile gives sex, age, height, weight and activity', () async {
      given(profile: Stream.value(man));

      expect(
        await getKnownValues('u1'),
        const KnownBodyValues(
          sex: Sex.male,
          ageYears: 36,
          heightCm: 180,
          weightKg: 82,
          activity: ActivityLevel.moderate,
        ),
      );
    });

    test('the newest entry with a weight wins over the profile', () async {
      given(
        profile: Stream.value(man),
        entries: Stream.value([
          entry(
            'e3',
            DateTime(2026, 11, 10),
            measurements: {BodyMeasurement.waist: 84},
          ),
          entry('e2', DateTime(2026, 11, 3), weightKg: 80.4),
          entry('e1', DateTime(2026, 10, 27), weightKg: 81),
        ]),
      );

      expect((await getKnownValues('u1')).weightKg, 80.4);
    });

    test('without a weight in any entry the profile weight stays', () async {
      given(
        profile: Stream.value(man),
        entries: Stream.value([
          entry(
            'e1',
            DateTime(2026, 11, 10),
            measurements: {BodyMeasurement.waist: 84},
          ),
        ]),
      );

      expect((await getKnownValues('u1')).weightKg, 82);
    });

    test('each circumference comes from the newest entry that has it, '
        'and the body fat from them', () async {
      given(
        profile: Stream.value(man),
        entries: Stream.value([
          entry(
            'e3',
            DateTime(2026, 11, 10),
            measurements: {BodyMeasurement.waist: 84, BodyMeasurement.chest: 1},
          ),
          entry(
            'e2',
            DateTime(2026, 11, 3),
            measurements: {BodyMeasurement.waist: 86, BodyMeasurement.hips: 98},
          ),
          entry(
            'e1',
            DateTime(2026, 9, 1),
            measurements: {BodyMeasurement.neck: 39},
          ),
        ]),
      );

      final known = await getKnownValues('u1');

      expect(known.neckCm, 39);
      expect(known.waistCm, 84);
      expect(known.hipCm, 98);
      expect(
        known.bodyFatPercent,
        navy(sex: Sex.male, heightCm: 180, neckCm: 39, waistCm: 84),
      );
    });

    test('a woman needs the hips for a body fat', () async {
      final woman = const UserProfile(sex: Sex.female, heightCm: 165);
      final withoutHips = [
        entry(
          'e1',
          DateTime(2026, 11, 3),
          measurements: {BodyMeasurement.neck: 33, BodyMeasurement.waist: 70},
        ),
      ];
      given(profile: Stream.value(woman), entries: Stream.value(withoutHips));
      expect((await getKnownValues('u1')).bodyFatPercent, isNull);

      given(
        profile: Stream.value(woman),
        entries: Stream.value([
          entry(
            'e2',
            DateTime(2026, 11, 10),
            measurements: {BodyMeasurement.hips: 95},
          ),
          ...withoutHips,
        ]),
      );
      expect(
        (await getKnownValues('u1')).bodyFatPercent,
        navy(
          sex: Sex.female,
          heightCm: 165,
          neckCm: 33,
          waistCm: 70,
          hipCm: 95,
        ),
      );
    });

    test('no body fat without sex or height, or from impossible '
        'measurements', () async {
      final measured = Stream.value([
        entry(
          'e1',
          DateTime(2026, 11, 3),
          measurements: {BodyMeasurement.neck: 39, BodyMeasurement.waist: 84},
        ),
      ]);
      given(
        profile: Stream.value(const UserProfile(heightCm: 180)),
        entries: measured,
      );
      expect((await getKnownValues('u1')).bodyFatPercent, isNull);

      given(
        profile: Stream.value(const UserProfile(sex: Sex.male)),
        entries: Stream.value([
          entry(
            'e1',
            DateTime(2026, 11, 3),
            measurements: {BodyMeasurement.neck: 39, BodyMeasurement.waist: 84},
          ),
        ]),
      );
      expect((await getKnownValues('u1')).bodyFatPercent, isNull);

      // The waist smaller than the neck.
      given(
        profile: Stream.value(man),
        entries: Stream.value([
          entry(
            'e1',
            DateTime(2026, 11, 3),
            measurements: {BodyMeasurement.neck: 45, BodyMeasurement.waist: 44},
          ),
        ]),
      );
      final known = await getKnownValues('u1');
      expect(known.bodyFatPercent, isNull);
      expect(known.neckCm, 45);
    });

    test('nothing known leaves every value empty', () async {
      given();

      expect(await getKnownValues('u1'), const KnownBodyValues());
    });

    test('a source that fails adds nothing; the other still does', () async {
      given(
        profile: Stream.error(const NetworkFailure('off')),
        entries: Stream.value([
          entry('e1', DateTime(2026, 11, 3), weightKg: 80),
        ]),
      );
      expect(await getKnownValues('u1'), const KnownBodyValues(weightKg: 80));

      given(
        profile: Stream.value(man),
        entries: Stream.error(const NetworkFailure('off')),
      );
      expect((await getKnownValues('u1')).weightKg, 82);
    });
  });

  test('training days map onto the activity levels', () {
    expect(activityFor(2), ActivityLevel.light);
    expect(activityFor(3), ActivityLevel.moderate);
    expect(activityFor(5), ActivityLevel.moderate);
    expect(activityFor(6), ActivityLevel.active);
  });
}
