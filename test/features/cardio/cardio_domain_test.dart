import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/cardio/domain/cardio_repository.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/cardio/domain/cardio_usecases.dart';
import 'package:get_workout/features/cardio/domain/cardio_validation.dart';
import 'package:get_workout/features/cardio/domain/cardio_week.dart';
import 'package:mocktail/mocktail.dart';

class MockCardioRepository extends Mock implements CardioRepository {}

CardioSession session({
  CardioType type = CardioType.outdoorRun,
  DateTime? date,
  Duration duration = const Duration(minutes: 30),
  double? distanceKm,
  int? calories,
  int? avgHeartRate,
  double? incline,
}) => CardioSession(
  type: type,
  date: date ?? DateTime(2026, 11, 10, 7),
  duration: duration,
  distanceKm: distanceKm,
  calories: calories,
  avgHeartRate: avgHeartRate,
  incline: incline,
);

void main() {
  group('CardioType', () {
    test('every stored code reads back as its type', () {
      for (final type in CardioType.values) {
        expect(CardioType.fromCode(type.code), type);
      }
    });

    test('an unknown code reads as other', () {
      expect(CardioType.fromCode('unicycle'), CardioType.other);
      expect(CardioType.fromCode(null), CardioType.other);
    });

    test('distance, incline and rate fit the activity', () {
      final withDistance = {
        for (final t in CardioType.values)
          if (t.distance) t,
      };
      expect(withDistance, {
        CardioType.treadmillRun,
        CardioType.treadmillWalk,
        CardioType.outdoorRun,
        CardioType.outdoorWalk,
        CardioType.hiking,
        CardioType.stationaryBike,
        CardioType.outdoorCycle,
        CardioType.rowing,
        CardioType.swimming,
      });
      expect(
        {
          for (final t in CardioType.values)
            if (t.incline) t,
        },
        {
          CardioType.treadmillRun,
          CardioType.treadmillWalk,
          CardioType.stairClimber,
        },
      );
      expect(CardioType.outdoorRun.rate, CardioRate.pace);
      expect(CardioType.hiking.rate, CardioRate.pace);
      expect(CardioType.outdoorCycle.rate, CardioRate.speed);
      expect(CardioType.stationaryBike.rate, CardioRate.speed);
    });
  });

  group('pace and speed', () {
    final run = session(duration: const Duration(minutes: 50), distanceKm: 10);

    test('pace per km and per mile', () {
      expect(run.pace(DistanceUnit.km), const Duration(minutes: 5));
      // 10 km = 6.2137 mi; 50 min / 6.2137 = 8:02.7
      expect(run.pace(DistanceUnit.mile)!.inMilliseconds, closeTo(482803, 1));
    });

    test('speed in km/h and mph', () {
      expect(run.speed(DistanceUnit.km), closeTo(12, 1e-9));
      expect(run.speed(DistanceUnit.mile), closeTo(7.4565, 1e-4));
    });

    test('no distance gives neither', () {
      final bare = session();
      expect(bare.pace(DistanceUnit.km), isNull);
      expect(bare.speed(DistanceUnit.km), isNull);
    });

    test('zero duration gives no speed', () {
      final instant = session(duration: Duration.zero, distanceKm: 5);
      expect(instant.speed(DistanceUnit.km), isNull);
    });

    test('miles convert both ways', () {
      expect(DistanceUnit.mile.toKm(1), 1.609344);
      expect(DistanceUnit.mile.fromKm(1.609344), 1);
      expect(DistanceUnit.km.toKm(5), 5);
    });
  });

  group('validateCardio', () {
    final now = DateTime(2026, 11, 11, 12);
    Set<CardioIssue> check(CardioSession s) => validateCardio(s, now: now);

    test('a plain session is valid', () {
      expect(
        check(
          session(
            type: CardioType.treadmillRun,
            distanceKm: 5,
            calories: 400,
            avgHeartRate: 150,
            incline: 2,
          ),
        ),
        isEmpty,
      );
    });

    test('duration must be above zero and at most 24 hours', () {
      expect(check(session(duration: Duration.zero)), {
        CardioIssue.durationMissing,
      });
      expect(check(session(duration: const Duration(hours: 24))), isEmpty);
      expect(check(session(duration: const Duration(hours: 24, seconds: 1))), {
        CardioIssue.durationTooLong,
      });
    });

    test('the start may be now but not later', () {
      expect(check(session(date: now)), isEmpty);
      expect(check(session(date: now.add(const Duration(minutes: 1)))), {
        CardioIssue.dateInFuture,
      });
    });

    test('distance must be above zero and at most 500 km', () {
      expect(check(session(distanceKm: 0)), {CardioIssue.distanceOutOfRange});
      expect(check(session(distanceKm: 500)), isEmpty);
      expect(check(session(distanceKm: 500.1)), {
        CardioIssue.distanceOutOfRange,
      });
    });

    test('calories must be 1 to 10000', () {
      expect(check(session(calories: 0)), {CardioIssue.caloriesOutOfRange});
      expect(check(session(calories: 1)), isEmpty);
      expect(check(session(calories: 10000)), isEmpty);
      expect(check(session(calories: 10001)), {CardioIssue.caloriesOutOfRange});
    });

    test('heart rate must be 30 to 240', () {
      expect(check(session(avgHeartRate: 29)), {
        CardioIssue.heartRateOutOfRange,
      });
      expect(check(session(avgHeartRate: 30)), isEmpty);
      expect(check(session(avgHeartRate: 240)), isEmpty);
      expect(check(session(avgHeartRate: 241)), {
        CardioIssue.heartRateOutOfRange,
      });
    });

    test('incline must be -10 to 40 percent', () {
      CardioSession treadmill(double incline) =>
          session(type: CardioType.treadmillWalk, incline: incline);
      expect(check(treadmill(-10)), isEmpty);
      expect(check(treadmill(40)), isEmpty);
      expect(check(treadmill(-10.5)), {CardioIssue.inclineOutOfRange});
      expect(check(treadmill(41)), {CardioIssue.inclineOutOfRange});
    });

    test('fields the type does not use are ignored', () {
      expect(
        check(session(type: CardioType.hiit, distanceKm: -1, incline: 99)),
        isEmpty,
      );
    });

    test('reports every issue at once', () {
      expect(
        check(
          session(
            duration: Duration.zero,
            date: now.add(const Duration(days: 1)),
            avgHeartRate: 300,
          ),
        ),
        {
          CardioIssue.durationMissing,
          CardioIssue.dateInFuture,
          CardioIssue.heartRateOutOfRange,
        },
      );
    });
  });

  group('SaveCardioSession', () {
    late MockCardioRepository repository;
    late SaveCardioSession save;
    final now = DateTime(2026, 11, 11, 12);

    setUpAll(() => registerFallbackValue(session()));

    setUp(() {
      repository = MockCardioRepository();
      save = SaveCardioSession(repository, clock: () => now);
      when(() => repository.saveSession(any(), any()))
          .thenAnswer((_) async => const Ok(null));
    });

    test('saves a valid session for the user', () async {
      final valid = session(distanceKm: 5);
      expect((await save((uid: 'u1', session: valid))).isOk, isTrue);
      verify(() => repository.saveSession('u1', valid)).called(1);
    });

    test('refuses an invalid session without touching storage', () async {
      final result = await save((
        uid: 'u1',
        session: session(duration: Duration.zero),
      ));
      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => repository.saveSession(any(), any()));
    });
  });

  group('weeks', () {
    CardioSession at(DateTime date, {int minutes = 30, double? km}) => session(
      date: date,
      duration: Duration(minutes: minutes),
      distanceKm: km,
    );

    test('a week starts on Monday at local midnight', () {
      // Wednesday 11 Nov 2026.
      expect(weekStart(DateTime(2026, 11, 11, 18, 30)), DateTime(2026, 11, 9));
      expect(weekStart(DateTime(2026, 11, 9)), DateTime(2026, 11, 9));
      // Sunday belongs to the week that began six days earlier.
      expect(weekStart(DateTime(2026, 11, 15, 23, 59)), DateTime(2026, 11, 9));
    });

    test('the week across New Year is one week', () {
      // Monday 29 Dec 2025 starts ISO week 1 of 2026.
      final start = DateTime(2025, 12, 29);
      expect(weekStart(DateTime(2025, 12, 31, 20)), start);
      expect(weekStart(DateTime(2026, 1, 4, 10)), start);
      expect(weekStart(DateTime(2026, 1, 5)), DateTime(2026, 1, 5));
    });

    test('groupByWeek keeps order and totals each week', () {
      final sessions = [
        at(DateTime(2026, 1, 6, 8), minutes: 20, km: 4),
        at(DateTime(2026, 1, 2, 8), minutes: 40, km: 8),
        at(DateTime(2025, 12, 29, 8), minutes: 25),
        at(DateTime(2025, 12, 21, 8), minutes: 60, km: 10),
      ];

      final weeks = groupByWeek(sessions);

      expect(weeks.map((w) => w.start), [
        DateTime(2026, 1, 5),
        DateTime(2025, 12, 29),
        DateTime(2025, 12, 15),
      ]);
      expect(weeks[1].sessions, [sessions[1], sessions[2]]);
      expect(weeks[1].duration, const Duration(minutes: 65));
      expect(weeks[1].distanceKm, 8);
      expect(weeks[1].count, 2);
    });

    test('lastWeeks gives 12 weeks oldest first, empty ones included', () {
      final now = DateTime(2026, 1, 8, 12);
      final sessions = [
        at(DateTime(2026, 1, 7), minutes: 30, km: 5),
        at(DateTime(2026, 1, 1), minutes: 45),
        at(DateTime(2025, 12, 30), minutes: 15, km: 3),
        // Before the window: ignored.
        at(DateTime(2025, 10, 1), minutes: 99),
      ];

      final weeks = lastWeeks(sessions, now: now);

      expect(weeks, hasLength(12));
      expect(weeks.last.start, DateTime(2026, 1, 5));
      expect(weeks.first.start, DateTime(2025, 10, 20));
      expect(weeks.last.duration, const Duration(minutes: 30));
      expect(weeks[10].start, DateTime(2025, 12, 29));
      expect(weeks[10].duration, const Duration(minutes: 60));
      expect(weeks[10].distanceKm, 3);
      expect(weeks[10].count, 2);
      expect(weeks.take(10).every((w) => w.count == 0), isTrue);
    });

    // Daylight saving starts on 29 Mar 2026 in the EU and 8 Mar 2026 in the
    // US, and ends on 25 Oct / 1 Nov. Run with TZ=Europe/Berlin or
    // TZ=America/New_York to exercise the shift; in UTC this still holds.
    test('every week starts at local midnight across DST changes', () {
      for (final now in [
        DateTime(2026, 4, 15, 12),
        DateTime(2026, 11, 20, 12),
      ]) {
        final weeks = lastWeeks(const [], now: now);
        for (final week in weeks) {
          expect(week.start.weekday, DateTime.monday, reason: '${week.start}');
          expect(week.start.hour, 0, reason: '${week.start}');
          expect(week.start.minute, 0, reason: '${week.start}');
        }
        for (var i = 1; i < weeks.length; i++) {
          final previous = weeks[i - 1].start;
          expect(
            weeks[i].start,
            DateTime(previous.year, previous.month, previous.day + 7),
          );
        }
      }
    });

    test('sessions around a DST change land in their local week', () {
      final now = DateTime(2026, 4, 1, 12);
      final sessions = [
        // Sunday night before the EU change, then Monday just after midnight.
        at(DateTime(2026, 3, 29, 23, 30), minutes: 10),
        at(DateTime(2026, 3, 30, 0, 30), minutes: 20),
        // Sunday of the US change.
        at(DateTime(2026, 3, 8, 3, 30), minutes: 40),
      ];

      final weeks = lastWeeks(sessions, now: now);

      expect(weeks.last.start, DateTime(2026, 3, 30));
      expect(weeks.last.duration, const Duration(minutes: 20));
      expect(weeks[10].start, DateTime(2026, 3, 23));
      expect(weeks[10].duration, const Duration(minutes: 10));
      expect(weeks[7].start, DateTime(2026, 3, 2));
      expect(weeks[7].duration, const Duration(minutes: 40));
    });
  });
}
