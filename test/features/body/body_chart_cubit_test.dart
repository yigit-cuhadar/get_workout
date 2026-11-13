import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';
import 'package:get_workout/features/body/domain/body_chart.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/presentation/body_chart_cubit.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/premium_status.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/steps/domain/steps_prompt.dart';
import 'package:get_workout/features/steps/domain/steps_usecases.dart';
import 'package:get_workout/features/strength/domain/strength.dart';
import 'package:get_workout/features/volume/domain/volume_usecases.dart';
import 'package:get_workout/features/volume/domain/weekly_volume.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBodyList extends MockCubit<BodyListState> implements BodyListCubit {}

class MockWatchVolume extends Mock implements WatchWeeklyVolume {}

/// Choices kept in memory; a load or save can be held or made to fail.
class MemoryChartStore implements BodyChartStore {
  final choices = <String, BodyChartChoice>{};
  final saved = <BodyChartChoice>[];
  Completer<void>? loadGate;
  Failure? saveFailure;

  @override
  Future<Result<BodyChartChoice?>> load(String uid) async {
    await loadGate?.future;
    return Ok(choices[uid]);
  }

  @override
  Future<Result<void>> save(String uid, BodyChartChoice choice) async {
    if (saveFailure case final failure?) return Err(failure);
    choices[uid] = choice;
    saved.add(choice);
    return const Ok(null);
  }
}

class FakePremium implements PremiumStatus {
  final controller = StreamController<bool?>.broadcast();

  @override
  Stream<bool?> watch() => controller.stream;
}

/// Counts the reads of daily steps; each waits for [gate] when set.
class CountingHealth extends FakeHealthSteps {
  CountingHealth({required super.clock})
    : super(permissionStatus: HealthPermission.granted, stepsFor: (_) => 7000);

  final reads = <DateTime>[];
  Completer<void>? gate;

  /// Holds the check for access while set.
  Completer<void>? accessGate;

  @override
  Future<Result<HealthAvailability>> availability() async {
    await accessGate?.future;
    return super.availability();
  }

  @override
  Future<Result<List<DailySteps>>> dailySteps(
    DateTime first,
    DateTime last,
  ) async {
    reads.add(first);
    await gate?.future;
    return super.dailySteps(first, last);
  }
}

class AskedPrompt implements StepsPrompt {
  @override
  Future<Result<bool>> askedHere() async => const Ok(true);

  @override
  Future<Result<void>> markAskedHere() async => const Ok(null);
}

void main() {
  const user = AuthUser(id: 'u1', isAnonymous: true);
  // A Thursday; 12 weeks back is Thursday, August 20.
  final now = DateTime(2026, 11, 12, 9);
  final recent = BodyEntry(
    id: 'r',
    date: DateTime(2026, 11, 10),
    weightKg: 80,
    measurements: const {BodyMeasurement.waist: 84},
  );
  final old = BodyEntry(id: 'o', date: DateTime(2026, 3, 1), weightKg: 86);
  final ready = BodyListState(
    status: BodyListStatus.ready,
    entries: [recent, old],
  );

  late MockAuthRepository auth;
  late StreamController<AuthUser?> users;
  late MockBodyList body;
  late StreamController<BodyListState> bodyStates;
  late MemoryChartStore stored;
  late FakePremium premium;
  late MockWatchVolume volume;
  late StreamController<List<WeekVolume>> weeks;
  late CountingHealth health;
  late BodyChartCubit cubit;

  setUpAll(() {
    registerFallbackValue((
      uid: '',
      lastWeek: CalendarDate(2026, 1, 1),
      weeks: 1,
      muscles: <String, ExerciseMuscles>{},
    ));
  });

  setUp(() {
    auth = MockAuthRepository();
    users = StreamController<AuthUser?>.broadcast();
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    body = MockBodyList();
    bodyStates = StreamController<BodyListState>.broadcast();
    whenListen(body, bodyStates.stream, initialState: ready);
    stored = MemoryChartStore();
    premium = FakePremium();
    volume = MockWatchVolume();
    weeks = StreamController<List<WeekVolume>>.broadcast();
    when(() => volume(any())).thenAnswer((_) => weeks.stream);
    health = CountingHealth(clock: () => now);
  });

  tearDown(() => cubit.close());

  Future<void> start({bool? isPremium = true}) async {
    cubit = BodyChartCubit(
      firstWeekday: DateTime.monday,
      body: body,
      watchAuthUser: WatchAuthUser(auth),
      watchPremium: WatchPremium(premium),
      loadChoice: LoadBodyChart(stored),
      saveChoice: SaveBodyChart(stored),
      watchVolume: volume,
      getStepsAccess: GetStepsAccess(health, AskedPrompt()),
      getDailySteps: GetDailySteps(health),
      clock: () => now,
    );
    users.add(user);
    premium.controller.add(isPremium);
    await pumpEventQueue();
  }

  Future<void> bodyIs(BodyListState state) async {
    when(() => body.state).thenReturn(state);
    bodyStates.add(state);
    await pumpEventQueue();
  }

  test('shows the weights of the range from its first day to now', () async {
    await start();

    expect(cubit.state.shown, [BodySeries.weight]);
    expect(cubit.state.from, DateTime(2026, 8, 20));
    expect(cubit.state.to, now);
    expect(cubit.state.points, {
      BodySeries.weight: [SeriesPoint(recent.date, 80)],
    });
    expect(cubit.state.axes, {BodySeries.weight: ChartAxis.left});
  });

  test('adds body fat by default once the user has some', () async {
    await start();

    await bodyIs(
      BodyListState(
        status: BodyListStatus.ready,
        entries: [recent, old],
        bodyFat: const {'r': 18},
      ),
    );

    expect(cubit.state.shown, [BodySeries.weight, BodySeries.bodyFat]);
    expect(cubit.state.points[BodySeries.bodyFat], [
      SeriesPoint(recent.date, 18),
    ]);
  });

  test('a series picked or removed is kept on the device', () async {
    await start();

    await cubit.toggle(BodySeries.waist);
    await pumpEventQueue();

    expect(
      stored.choices['u1'],
      const BodyChartChoice(series: [BodySeries.weight, BodySeries.waist]),
    );
    expect(cubit.state.shown, [BodySeries.weight, BodySeries.waist]);
    expect(cubit.state.points[BodySeries.waist], [
      SeriesPoint(recent.date, 84),
    ]);

    await cubit.toggle(BodySeries.weight);
    await pumpEventQueue();
    expect(cubit.state.shown, [BodySeries.waist]);
  });

  test('the target line switch is kept with the series', () async {
    await start();

    await cubit.showTargetLine(false);
    await pumpEventQueue();

    expect(
      stored.choices['u1'],
      const BodyChartChoice(series: [BodySeries.weight], targetLine: false),
    );
    expect(cubit.state.targetLine, isFalse);
  });

  test('the range applies to every series', () async {
    await start();

    await bodyIs(
      BodyListState(
        status: BodyListStatus.ready,
        entries: [recent, old],
        range: StrengthRange.all,
      ),
    );

    expect(cubit.state.from, DateTime(2026, 3, 1));
    expect(cubit.state.points[BodySeries.weight], hasLength(2));
  });

  group('weekly sets', () {
    WeekVolume week(CalendarDate start, int sets) => WeekVolume(start, [
      VolumeEntry(
        workoutId: 'w',
        workoutName: 'W',
        startedAt: start.toLocalDateTime(),
        exerciseId: 'e',
        exerciseName: 'E',
        sets: sets,
        muscles: (main: const [], secondary: const []),
      ),
    ]);

    test('are read only while shown, for whole weeks of the range', () async {
      await start();
      verifyNever(() => volume(any()));

      await cubit.toggle(BodySeries.weeklySets);
      await pumpEventQueue();

      final query =
          verify(() => volume(captureAny())).captured.single as VolumeQuery;
      expect(query.uid, 'u1');
      expect(query.lastWeek, CalendarDate(2026, 11, 9));
      expect(query.weeks, 13);
      expect(cubit.state.from, DateTime(2026, 8, 17));
      expect(cubit.state.to, DateTime(2026, 11, 16));
      expect(cubit.state.points[BodySeries.weeklySets], isEmpty);

      weeks.add([week(CalendarDate(2026, 11, 9), 12)]);
      await pumpEventQueue();
      expect(cubit.state.points[BodySeries.weeklySets], [
        SeriesPoint(DateTime(2026, 11, 9), 12),
      ]);
      expect(cubit.state.axes[BodySeries.weeklySets], ChartAxis.right);

      await cubit.toggle(BodySeries.weeklySets);
      await pumpEventQueue();
      expect(weeks.hasListener, isFalse);
    });

    test('are read again for another range, not for other changes', () async {
      await start();
      await cubit.toggle(BodySeries.weeklySets);
      await pumpEventQueue();
      await bodyIs(ready);

      await bodyIs(
        BodyListState(
          status: BodyListStatus.ready,
          entries: [recent, old],
          range: StrengthRange.all,
        ),
      );

      final queries = verify(() => volume(captureAny())).captured;
      expect(queries, hasLength(2));
      // All reads from the earliest date a workout can have.
      final all = queries.last as VolumeQuery;
      expect(all.lastWeek, CalendarDate(2026, 11, 9));
      expect(
        all.lastWeek.addDays(-7 * (all.weeks - 1)),
        CalendarDate.of(earliestDate).startOfWeek(DateTime.monday),
      );
      expect(cubit.state.from, DateTime(2026, 2, 23));

      // ... and starts at the oldest value of any series shown.
      weeks.add([
        WeekVolume(CalendarDate(2025, 1, 6), const []),
        week(CalendarDate(2025, 1, 13), 5),
        week(CalendarDate(2026, 11, 9), 12),
      ]);
      await pumpEventQueue();
      expect(cubit.state.from, DateTime(2025, 1, 13));
      expect(cubit.state.points[BodySeries.weeklySets], hasLength(2));
    });

    test('show loading until read, a failure until retried', () async {
      await start();
      await cubit.toggle(BodySeries.weeklySets);
      await pumpEventQueue();
      expect(cubit.state.loading, {BodySeries.weeklySets});

      weeks.addError(const NetworkFailure());
      await pumpEventQueue();
      expect(cubit.state.loading, isEmpty);
      expect(cubit.state.failed, {BodySeries.weeklySets});

      cubit.retry(BodySeries.weeklySets);
      await pumpEventQueue();
      expect(cubit.state.failed, isEmpty);
      expect(cubit.state.loading, {BodySeries.weeklySets});
      verify(() => volume(any())).called(2);

      // Taken off and on again reads again too.
      weeks.addError(const NetworkFailure());
      await pumpEventQueue();
      await cubit.toggle(BodySeries.weeklySets);
      await cubit.toggle(BodySeries.weeklySets);
      await pumpEventQueue();
      expect(cubit.state.failed, isEmpty);
      verify(() => volume(any())).called(1);
    });
  });

  group('Premium', () {
    test(
      'while unknown, training series are neither locked nor read',
      () async {
        stored.choices['u1'] = const BodyChartChoice(
          series: [BodySeries.weeklySets, BodySeries.waist],
        );

        await start(isPremium: null);

        expect(cubit.state.premium, isNull);
        expect(cubit.state.locked(BodySeries.weeklySets), isFalse);
        expect(cubit.state.shown, [BodySeries.waist]);
        verifyNever(() => volume(any()));
      },
    );

    test('unlocking only adds, also when Premium came first', () async {
      stored.choices['u1'] = const BodyChartChoice(
        series: [BodySeries.weeklySets, BodySeries.weight],
      );
      await start(isPremium: false);
      expect(cubit.state.shown, [BodySeries.weight]);

      // The purchase arrives before the paywall closes.
      premium.controller.add(true);
      await pumpEventQueue();
      await cubit.add(BodySeries.weeklySets);

      expect(cubit.state.shown, [BodySeries.weeklySets, BodySeries.weight]);
      expect(stored.saved, isEmpty);

      await cubit.add(BodySeries.dailySteps);
      expect(cubit.state.shown, [
        BodySeries.weeklySets,
        BodySeries.weight,
        BodySeries.dailySteps,
      ]);
    });

    test(
      'with only hidden series stored, a change builds on the default',
      () async {
        stored.choices['u1'] = const BodyChartChoice(
          series: [BodySeries.weeklySets],
        );
        await bodyIs(
          BodyListState(
            status: BodyListStatus.ready,
            entries: [recent, old],
            bodyFat: const {'r': 18},
          ),
        );
        await start(isPremium: false);
        expect(cubit.state.shown, [BodySeries.weight, BodySeries.bodyFat]);

        await cubit.toggle(BodySeries.bodyFat);

        expect(cubit.state.shown, [BodySeries.weight]);
        // The hidden one stays stored.
        expect(stored.choices['u1']!.series, [
          BodySeries.weeklySets,
          BodySeries.weight,
        ]);
      },
    );
    test(
      'a free user sees the training series locked and never reads them',
      () async {
        stored.choices['u1'] = const BodyChartChoice(
          series: [
            BodySeries.weeklySets,
            BodySeries.dailySteps,
            BodySeries.waist,
          ],
        );

        await start(isPremium: false);

        expect(cubit.state.locked(BodySeries.weeklySets), isTrue);
        expect(cubit.state.locked(BodySeries.waist), isFalse);
        expect(cubit.state.shown, [BodySeries.waist]);
        verifyNever(() => volume(any()));
        expect(health.reads, isEmpty);
        // Kept, not deleted.
        expect(stored.saved, isEmpty);

        premium.controller.add(true);
        await pumpEventQueue();
        expect(cubit.state.shown, [
          BodySeries.weeklySets,
          BodySeries.dailySteps,
          BodySeries.waist,
        ]);
        verify(() => volume(any())).called(1);
        expect(health.reads, isNotEmpty);
      },
    );

    test('a picked training series shows once Premium comes', () async {
      await start(isPremium: false);

      await cubit.toggle(BodySeries.weeklySets);
      expect(cubit.state.shown, [BodySeries.weight]);

      premium.controller.add(true);
      await pumpEventQueue();
      expect(cubit.state.shown, [BodySeries.weight, BodySeries.weeklySets]);
    });
  });

  group('the choice', () {
    test('builds on the one made, however fast the taps', () async {
      await start();

      unawaited(cubit.toggle(BodySeries.waist));
      unawaited(cubit.toggle(BodySeries.thigh));
      await pumpEventQueue();

      const both = BodyChartChoice(
        series: [BodySeries.weight, BodySeries.waist, BodySeries.thigh],
      );
      expect(cubit.state.shown, both.series);
      expect(stored.choices['u1'], both);
    });

    test('keeps a stored series that does not show yet', () async {
      stored.choices['u1'] = const BodyChartChoice(
        series: [BodySeries.dailySteps, BodySeries.weight],
      );
      // Access is still being checked: steps do not show yet.
      final access = Completer<void>();
      health.accessGate = access;
      await start();
      expect(cubit.state.shown, [BodySeries.weight]);

      await cubit.toggle(BodySeries.waist);

      expect(stored.choices['u1']!.series, [
        BodySeries.dailySteps,
        BodySeries.weight,
        BodySeries.waist,
      ]);
      access.complete();
    });

    test('is never written before the stored one is read', () async {
      stored.loadGate = Completer<void>();
      stored.choices['u1'] = const BodyChartChoice(series: [BodySeries.hips]);
      await start();

      await cubit.toggle(BodySeries.waist);
      expect(stored.saved, isEmpty);

      stored.loadGate!.complete();
      await pumpEventQueue();
      expect(cubit.state.shown, [BodySeries.hips]);
    });

    test('a failed save is told once', () async {
      stored.saveFailure = const UnknownFailure('disk full');
      await start();

      await cubit.toggle(BodySeries.waist);
      expect(cubit.state.saveFailed, isTrue);

      cubit.saveFailureShown();
      expect(cubit.state.saveFailed, isFalse);
    });

    test('is each user\'s own', () async {
      stored.choices['u2'] = const BodyChartChoice(series: [BodySeries.hips]);
      await start();
      expect(cubit.state.shown, [BodySeries.weight]);

      users.add(const AuthUser(id: 'u2', isAnonymous: false));
      await pumpEventQueue();
      expect(cubit.state.shown, [BodySeries.hips]);
    });
  });

  group('daily steps', () {
    test('are offered and averaged per week where they can be read', () async {
      await start();
      expect(cubit.state.available, contains(BodySeries.dailySteps));

      await cubit.toggle(BodySeries.dailySteps);
      await pumpEventQueue();

      final points = cubit.state.points[BodySeries.dailySteps]!;
      expect(points, hasLength(13));
      expect(points.first, SeriesPoint(DateTime(2026, 8, 17), 7000));
    });

    test('a read for another range stops between its spans', () async {
      await bodyIs(
        BodyListState(
          status: BodyListStatus.ready,
          entries: [
            recent,
            BodyEntry(id: 'a', date: DateTime(2023, 1, 2), weightKg: 90),
          ],
          range: StrengthRange.all,
        ),
      );
      stored.choices['u1'] = const BodyChartChoice(
        series: [BodySeries.dailySteps],
      );
      health.gate = Completer<void>();
      await start();
      expect(health.reads, hasLength(1));

      await bodyIs(ready);
      health.gate!.complete();
      await pumpEventQueue();

      // The 12 weeks were read; nothing more of All.
      expect(health.reads, [DateTime(2023, 1, 2), DateTime(2026, 8, 17)]);
      expect(cubit.state.points[BodySeries.dailySteps], hasLength(13));
    });

    test('only the latest read applies, also back to the same range', () async {
      final all = BodyListState(
        status: BodyListStatus.ready,
        entries: [
          recent,
          BodyEntry(id: 'a', date: DateTime(2023, 1, 2), weightKg: 90),
        ],
        range: StrengthRange.all,
      );
      await bodyIs(all);
      stored.choices['u1'] = const BodyChartChoice(
        series: [BodySeries.dailySteps],
      );
      health.gate = Completer<void>();
      await start();

      await bodyIs(ready);
      // The 12 weeks' steps are gone with their weeks.
      expect(cubit.state.loading, {BodySeries.dailySteps});
      await bodyIs(all);
      health.gate!.complete();
      await pumpEventQueue();

      // Three reads started; the two superseded stopped after one span, the
      // last read all four.
      expect(health.reads, hasLength(6));
      expect(cubit.state.loading, isEmpty);
    });

    test('are read again when asked, e.g. back in the app', () async {
      stored.choices['u1'] = const BodyChartChoice(
        series: [BodySeries.dailySteps],
      );
      await start();
      expect(health.reads, hasLength(1));

      cubit.refreshSteps();
      await pumpEventQueue();

      expect(health.reads, hasLength(2));
    });

    test('are neither offered nor shown without access', () async {
      health.permissionStatus = HealthPermission.denied;
      stored.choices['u1'] = const BodyChartChoice(
        series: [BodySeries.dailySteps, BodySeries.weight],
      );

      await start();

      expect(cubit.state.available, isNot(contains(BodySeries.dailySteps)));
      expect(cubit.state.shown, [BodySeries.weight]);
    });
  });
}
