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
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/settings/domain/settings_repository.dart';
import 'package:get_workout/features/settings/domain/settings_usecases.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/steps/domain/steps_prompt.dart';
import 'package:get_workout/features/steps/domain/steps_usecases.dart';
import 'package:get_workout/features/strength/domain/strength.dart';
import 'package:get_workout/features/volume/domain/volume_usecases.dart';
import 'package:get_workout/features/volume/domain/weekly_volume.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBodyList extends MockCubit<BodyListState> implements BodyListCubit {}

class MockWatchVolume extends Mock implements WatchWeeklyVolume {}

/// Settings kept in memory; a save comes back through the stream.
class MemorySettings implements SettingsRepository {
  MemorySettings(this.current);

  UserSettings current;
  final _saved = StreamController<UserSettings>.broadcast();

  @override
  Stream<UserSettings> watchSettings(String uid) async* {
    yield current;
    yield* _saved.stream;
  }

  @override
  Future<Result<void>> saveSettings(String uid, UserSettings settings) async {
    current = settings;
    _saved.add(settings);
    return const Ok(null);
  }

  @override
  Future<Result<void>> markTipSeen(String uid, Tip tip) async => const Ok(null);
}

class AskedPrompt implements StepsPrompt {
  @override
  Future<Result<bool>> askedHere() async => const Ok(true);

  @override
  Future<Result<void>> markAskedHere() async => const Ok(null);
}

void main() {
  const user = AuthUser(id: 'u1', isAnonymous: true);
  const defaults = UserSettings(
    weightUnit: WeightUnit.kg,
    lengthUnit: LengthUnit.cm,
  );
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
  late MemorySettings stored;
  late SettingsCubit settings;
  late MockWatchVolume volume;
  late StreamController<List<WeekVolume>> weeks;
  late FakeHealthSteps health;
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
    stored = MemorySettings(defaults);
    settings = SettingsCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchSettings: WatchSettings(stored),
      updateSettings: UpdateSettings(stored),
      markTipSeen: MarkTipSeen(stored),
      defaults: defaults,
    );
    volume = MockWatchVolume();
    weeks = StreamController<List<WeekVolume>>.broadcast();
    when(() => volume(any())).thenAnswer((_) => weeks.stream);
    health = FakeHealthSteps(
      permissionStatus: HealthPermission.granted,
      stepsFor: (_) => 7000,
      clock: () => now,
    );
  });

  tearDown(() async {
    await cubit.close();
    await settings.close();
  });

  Future<void> start() async {
    cubit = BodyChartCubit(
      firstWeekday: DateTime.monday,
      body: body,
      settings: settings,
      watchAuthUser: WatchAuthUser(auth),
      watchVolume: volume,
      getStepsAccess: GetStepsAccess(health, AskedPrompt()),
      getDailySteps: GetDailySteps(health),
      clock: () => now,
    );
    users.add(user);
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

  test('a series picked or removed is kept in the settings', () async {
    await start();

    await cubit.toggle(BodySeries.waist);
    await pumpEventQueue();

    expect(
      stored.current.bodyChart,
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
      stored.current.bodyChart,
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
      expect((queries.last as VolumeQuery).lastWeek, CalendarDate(2026, 11, 9));
      expect(cubit.state.from, DateTime(2026, 2, 23));
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

    test('are neither offered nor shown without access', () async {
      health.permissionStatus = HealthPermission.denied;
      stored.current = defaults.copyWith(
        bodyChart: const BodyChartChoice(
          series: [BodySeries.dailySteps, BodySeries.weight],
        ),
      );

      await start();

      expect(cubit.state.available, isNot(contains(BodySeries.dailySteps)));
      expect(cubit.state.shown, [BodySeries.weight]);
    });
  });
}
