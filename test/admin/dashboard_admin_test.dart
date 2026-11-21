import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/dashboard/data/dashboard_maps.dart';
import 'package:get_workout/admin/dashboard/data/firestore_admin_dashboard_repository.dart';
import 'package:get_workout/admin/dashboard/domain/admin_dashboard_repository.dart';
import 'package:get_workout/admin/dashboard/domain/dashboard.dart';
import 'package:get_workout/admin/dashboard/domain/dashboard_admin_usecases.dart';
import 'package:get_workout/admin/dashboard/presentation/dashboard_cubit.dart';
import 'package:get_workout/admin/dashboard/presentation/dashboard_format.dart';
import 'package:mocktail/mocktail.dart';

class MockFunctions extends Mock implements FirebaseFunctions {}

class MockCallable extends Mock implements HttpsCallable {}

class MockCallableResult extends Mock implements HttpsCallableResult<Object?> {}

class MockAdminDashboardRepository extends Mock
    implements AdminDashboardRepository {}

class FunctionsError extends FirebaseFunctionsException {
  FunctionsError(String code, {String? reason})
    : super(
        code: code,
        message: 'error',
        details: reason == null ? null : {'reason': reason},
      );
}

Map<String, Object?> _tile(num? value, num? previous) => {
  'value': value,
  'previous': previous,
};

/// A report as `buildReport` writes it.
Map<String, Object?> _reportMap({String from = '2026-11-14'}) => {
  'status': 'ok',
  'from': from,
  'to': '2026-11-20',
  'tiles': {
    'dailyActiveUsers': _tile(12.5, 10),
    'monthlyActiveUsers': _tile(80, null),
    'newUsers': _tile(20, 25),
    'onboardingCompleted': _tile(0.75, 0.7),
    'firstWorkout': _tile(0.5, 0.5),
    'workoutsCompleted': _tile(40, 30),
    'trialStarts': _tile(3, 2),
    'paidConversion': _tile(0.05, null),
    'mrr': _tile(null, null),
    'crashFreeUsers': _tile(0.99, 0.98),
  },
  'growth': [
    {'day': '2026-11-14', 'active': 10, 'new': 3},
    {'day': '2026-11-15', 'active': 15, 'new': 4},
  ],
  'funnel': {
    'installed': 20,
    'onboardingComplete': 15,
    'firstWorkout': 10,
    'paywallSeen': 8,
    'trialStarted': 3,
    'paid': 1,
  },
  'usage': {
    'programStarts': 6,
    'workoutsPerActiveUser': 1.5,
    'customExercisesCreated': 2,
    'weightsLogged': 9,
    'notificationsOpened': 4,
    'topProgram': {'id': 'ppl_beginner', 'starts': 3},
  },
  'quality': {
    'crashFreeUsers': 0.99,
    'handledErrors': 5,
    'topIssues': [
      {'title': 'StateError', 'users': 2},
    ],
  },
};

final _report = Report(
  range: DayRange(DateTime.utc(2026, 11, 14), DateTime.utc(2026, 11, 20)),
  tiles: const {
    DashboardTile.dailyActiveUsers: TileValue(value: 12.5, previous: 10),
    DashboardTile.monthlyActiveUsers: TileValue(value: 80),
    DashboardTile.newUsers: TileValue(value: 20, previous: 25),
    DashboardTile.onboardingCompleted: TileValue(value: 0.75, previous: 0.7),
    DashboardTile.firstWorkout: TileValue(value: 0.5, previous: 0.5),
    DashboardTile.workoutsCompleted: TileValue(value: 40, previous: 30),
    DashboardTile.trialStarts: TileValue(value: 3, previous: 2),
    DashboardTile.paidConversion: TileValue(value: 0.05),
    DashboardTile.mrr: TileValue(),
    DashboardTile.crashFreeUsers: TileValue(value: 0.99, previous: 0.98),
  },
  growth: [
    DayCount(day: DateTime.utc(2026, 11, 14), active: 10, newUsers: 3),
    DayCount(day: DateTime.utc(2026, 11, 15), active: 15, newUsers: 4),
  ],
  funnel: const Funnel(
    installed: 20,
    onboardingComplete: 15,
    firstWorkout: 10,
    paywallSeen: 8,
    trialStarted: 3,
    paid: 1,
  ),
  usage: const Usage(
    programStarts: 6,
    workoutsPerActiveUser: 1.5,
    customExercisesCreated: 2,
    weightsLogged: 9,
    notificationsOpened: 4,
    topProgramId: 'ppl_beginner',
    topProgramStarts: 3,
  ),
  quality: const Quality(
    crashFreeUsers: 0.99,
    handledErrors: 5,
    topIssues: [Issue(title: 'StateError', users: 2)],
  ),
);

final _range = DayRange(DateTime.utc(2026, 10, 1), DateTime.utc(2026, 10, 31));

void main() {
  group('DashboardMaps', () {
    test('reads a report as the functions write it', () {
      expect(DashboardMaps.report(_reportMap()), _report);
    });

    test('reads a missing or odd field as unknown', () {
      final report = DashboardMaps.report({
        'from': '2026-02-30',
        'to': '2026-11-20',
        'tiles': {
          'newUsers': {'value': '20'},
          'mrr': 3,
        },
        'growth': [
          {'day': 'yesterday', 'active': 1},
          {'day': '2026-11-20', 'active': 2.0, 'new': null},
          'odd',
        ],
        'usage': {'topProgram': null},
        'quality': {'topIssues': 'none'},
      });

      expect(report.range, isNull);
      expect(report.tiles.keys, DashboardTile.values);
      expect(report.tiles.values.toSet(), {const TileValue()});
      expect(report.growth, [
        DayCount(day: DateTime.utc(2026, 11, 20), active: 2),
      ]);
      expect(report.funnel, const Funnel());
      expect(report.usage, const Usage());
      expect(report.quality, const Quality());
    });

    test('reads retention, revenue and status', () {
      expect(
        DashboardMaps.retention({
          'status': 'ok',
          'cohorts': [
            {'week': '2026-10-05', 'users': 8, 'd1': 0.5, 'd7': 0.25},
            {'week': '2026-10-12', 'users': 0, 'd1': null},
          ],
        }),
        [
          Cohort(week: DateTime.utc(2026, 10, 5), users: 8, d1: 0.5, d7: 0.25),
          Cohort(week: DateTime.utc(2026, 10, 12), users: 0),
        ],
      );
      expect(
        DashboardMaps.revenue({
          'mrr': 120.5,
          'revenue28d': 300,
          'activeSubscriptions': 12,
          'activeTrials': null,
          'newCustomers28d': 40,
          'currency': 'USD',
          'day': '2026-11-21',
        }),
        const RevenueSnapshot(
          mrr: 120.5,
          revenue28d: 300,
          activeSubscriptions: 12,
          currency: 'USD',
        ),
      );
      expect(
        DashboardMaps.status({
          'lastDay': '2026-11-20',
          'updatedAtMillis': 1700000000000,
          'state': 'error',
          'message': 'p90: timeout',
        }),
        DashboardStatus(
          state: RefreshState.error,
          lastDay: DateTime.utc(2026, 11, 20),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          message: 'p90: timeout',
        ),
      );
      expect(
        DashboardMaps.status({'lastDay': null, 'state': 'no-data'}),
        const DashboardStatus(state: RefreshState.noData),
      );
      expect(
        DashboardMaps.status({'state': 'later'}).state,
        RefreshState.unknown,
      );
    });
  });

  group('FirestoreAdminDashboardRepository', () {
    late FakeFirebaseFirestore firestore;
    late MockFunctions functions;
    late MockCallable callable;
    late MockCallableResult result;
    late FirestoreAdminDashboardRepository repository;

    setUpAll(() => registerFallbackValue(HttpsCallableOptions()));

    setUp(() {
      firestore = FakeFirebaseFirestore();
      functions = MockFunctions();
      callable = MockCallable();
      result = MockCallableResult();
      repository = FirestoreAdminDashboardRepository(firestore, functions);
      when(() => functions.httpsCallable(any(), options: any(named: 'options')))
          .thenReturn(callable);
      when(() => callable.call<Object?>(any())).thenAnswer((_) async => result);
    });

    test('loads what is stored, and nothing before the first run', () async {
      expect((await repository.load()).valueOrNull, const DashboardData());

      final dashboard = firestore.collection('dashboard');
      await dashboard.doc('p7').set(_reportMap());
      await dashboard.doc('retention').set({'status': 'ok', 'cohorts': []});
      await dashboard.doc('revenue').set({'mrr': 10, 'currency': 'EUR'});
      await dashboard.doc('status').set({
        'lastDay': '2026-11-20',
        'updatedAtMillis': 1700000000000,
        'state': 'ok',
      });

      final data = (await repository.load()).valueOrNull!;
      expect(data.reports, {DashboardPreset.days7: _report});
      expect(data.retention, isEmpty);
      expect(data.revenue, const RevenueSnapshot(mrr: 10, currency: 'EUR'));
      expect(data.status?.state, RefreshState.ok);
      expect(data.hasNoData, isFalse);
    });

    test(
      'asks the range function for the days, and reads its report',
      () async {
        when(() => result.data).thenReturn(_reportMap());

        expect((await repository.report(_range)).valueOrNull, _report);
        verify(
          () => functions.httpsCallable(
            'dashboardRange',
            options: any(named: 'options'),
          ),
        ).called(1);
        verify(
          () => callable.call<Object?>({
            'from': '2026-10-01',
            'to': '2026-10-31',
          }),
        ).called(1);
      },
    );

    test('refreshes now and answers with the status', () async {
      when(
        () => result.data,
      ).thenReturn({'lastDay': null, 'updatedAtMillis': 1, 'state': 'no-data'});

      expect(
        (await repository.refresh()).valueOrNull?.state,
        RefreshState.noData,
      );
      verify(
        () => functions.httpsCallable(
          'dashboardRefresh',
          options: any(named: 'options'),
        ),
      ).called(1);
    });

    test('maps the refusals by their reason', () async {
      Future<Failure?> failureFor(FunctionsError error) async {
        when(() => callable.call<Object?>(any())).thenThrow(error);
        return (await repository.report(_range)).failureOrNull;
      }

      expect(
        await failureFor(
          FunctionsError('permission-denied', reason: 'not-admin'),
        ),
        isA<PermissionFailure>(),
      );
      expect(
        await failureFor(
          FunctionsError('invalid-argument', reason: 'invalid-input'),
        ),
        isA<ValidationFailure>(),
      );
      expect(
        await failureFor(
          FunctionsError('failed-precondition', reason: 'no-data'),
        ),
        isA<DashboardNoDataFailure>(),
      );
      expect(
        await failureFor(FunctionsError('unavailable')),
        isA<NetworkFailure>(),
      );
    });

    test('an answer that is not a map fails', () async {
      when(() => result.data).thenReturn('ok');
      expect((await repository.refresh()).failureOrNull, isA<UnknownFailure>());
    });
  });

  test('a custom range longer than the server allows is refused', () async {
    final repository = MockAdminDashboardRepository();
    final load = LoadRangeReport(repository);
    final year = DayRange(DateTime.utc(2025, 1, 1), DateTime.utc(2026, 1, 1));

    expect(year.days, 366);
    when(() => repository.report(year)).thenAnswer((_) async => Ok(_report));
    expect((await load(year)).valueOrNull, _report);

    final longer = DayRange(DateTime.utc(2025, 1, 1), DateTime.utc(2026, 1, 2));
    expect((await load(longer)).failureOrNull, isA<ValidationFailure>());
    verifyNever(() => repository.report(longer));
  });

  test('a tile change is in percent for counts, in points for shares', () {
    String? text(DashboardTile tile, double? value, double? previous) =>
        tileChange(tile, TileValue(value: value, previous: previous))?.text;

    expect(text(DashboardTile.newUsers, 108, 100), '▲ 8%');
    expect(text(DashboardTile.newUsers, 20, 25), '▼ 20%');
    expect(text(DashboardTile.newUsers, 0, 0), '0%');
    expect(text(DashboardTile.newUsers, 5, 0), isNull);
    expect(text(DashboardTile.newUsers, 5, null), isNull);
    expect(text(DashboardTile.paidConversion, 0.07, 0.05), '▲ 2 pts');
    expect(text(DashboardTile.crashFreeUsers, 0.985, 0.99), '▼ 0.5 pts');
    expect(text(DashboardTile.firstWorkout, 0.5, 0.5), '0 pts');
    expect(
      tileChange(
        DashboardTile.mrr,
        const TileValue(value: 90, previous: 100),
      )?.good,
      isFalse,
    );
    expect(
      tileChange(
        DashboardTile.dailyActiveUsers,
        const TileValue(value: 12.5, previous: 10),
      )?.good,
      isTrue,
    );
    expect(
      tileChange(
        DashboardTile.firstWorkout,
        const TileValue(value: 0.5, previous: 0.5),
      )?.good,
      isNull,
    );
  });

  group('DashboardCubit', () {
    late MockAdminDashboardRepository repository;
    final data = DashboardData(
      status: DashboardStatus(
        state: RefreshState.ok,
        lastDay: DateTime.utc(2026, 11, 20),
      ),
      reports: {DashboardPreset.days30: _report},
    );

    setUp(() {
      repository = MockAdminDashboardRepository();
      when(() => repository.load()).thenAnswer((_) async => Ok(data));
    });

    setUpAll(() => registerFallbackValue(_range));

    DashboardCubit build() => DashboardCubit(
      loadDashboard: LoadDashboard(repository),
      loadRangeReport: LoadRangeReport(repository),
      refreshDashboard: RefreshDashboard(repository),
    );

    blocTest<DashboardCubit, DashboardState>(
      'loads the stored reports and shows 30 days',
      build: build,
      expect: () => [DashboardState(data: data, loading: false)],
      verify: (cubit) => expect(cubit.state.report, _report),
    );

    blocTest<DashboardCubit, DashboardState>(
      'keeps a failed load to show',
      setUp: () =>
          when(() => repository.load())
              .thenAnswer((_) async => const Err(NetworkFailure())),
      build: build,
      expect: () => [
        const DashboardState(loading: false, failure: NetworkFailure()),
      ],
    );

    blocTest<DashboardCubit, DashboardState>(
      'a stored period with no report shows none',
      build: build,
      act: (cubit) async {
        await pumpEventQueue();
        cubit.selectPreset(DashboardPreset.days7);
      },
      skip: 1,
      expect: () => [
        DashboardState(
          data: data,
          loading: false,
          preset: DashboardPreset.days7,
        ),
      ],
      verify: (cubit) => expect(cubit.state.report, isNull),
    );

    blocTest<DashboardCubit, DashboardState>(
      'queries a custom range, then goes back to a stored period',
      setUp: () =>
          when(() => repository.report(_range))
              .thenAnswer((_) async => Ok(_report)),
      build: build,
      act: (cubit) async {
        await pumpEventQueue();
        await cubit.selectRange(_range);
        cubit.selectPreset(DashboardPreset.days90);
      },
      skip: 1,
      expect: () => [
        DashboardState(
          data: data,
          loading: false,
          customRange: _range,
          customLoading: true,
        ),
        DashboardState(
          data: data,
          loading: false,
          customRange: _range,
          customReport: _report,
        ),
        DashboardState(
          data: data,
          loading: false,
          preset: DashboardPreset.days90,
        ),
      ],
    );

    final pending = Completer<Result<Report>>();
    blocTest<DashboardCubit, DashboardState>(
      'drops a custom report that arrives after another period was chosen',
      setUp: () =>
          when(() => repository.report(_range))
              .thenAnswer((_) => pending.future),
      build: build,
      act: (cubit) async {
        await pumpEventQueue();
        final query = cubit.selectRange(_range);
        cubit.selectPreset(DashboardPreset.days30);
        pending.complete(Ok(_report));
        await query;
      },
      skip: 1,
      expect: () => [
        DashboardState(
          data: data,
          loading: false,
          customRange: _range,
          customLoading: true,
        ),
        DashboardState(data: data, loading: false),
      ],
    );

    blocTest<DashboardCubit, DashboardState>(
      'shows a refused custom range inline',
      setUp: () =>
          when(() => repository.report(_range))
              .thenAnswer((_) async => const Err(DashboardNoDataFailure())),
      build: build,
      act: (cubit) async {
        await pumpEventQueue();
        await cubit.selectRange(_range);
      },
      skip: 2,
      expect: () => [
        DashboardState(
          data: data,
          loading: false,
          customRange: _range,
          customFailure: const DashboardNoDataFailure(),
        ),
      ],
    );

    blocTest<DashboardCubit, DashboardState>(
      'refreshes now, then reads what was stored',
      setUp: () => when(() => repository.refresh()).thenAnswer(
        (_) async => const Ok(DashboardStatus(state: RefreshState.ok)),
      ),
      build: build,
      act: (cubit) async {
        await pumpEventQueue();
        await cubit.refresh();
      },
      skip: 1,
      expect: () => [
        DashboardState(data: data, loading: false, refreshing: true),
        DashboardState(data: data, loading: false),
        DashboardState(data: data),
        DashboardState(data: data, loading: false),
      ],
      verify: (_) => verify(() => repository.load()).called(2),
    );

    blocTest<DashboardCubit, DashboardState>(
      'a failed refresh keeps the data and says why',
      setUp: () =>
          when(() => repository.refresh())
              .thenAnswer((_) async => const Err(PermissionFailure())),
      build: build,
      act: (cubit) async {
        await pumpEventQueue();
        await cubit.refresh();
      },
      skip: 2,
      expect: () => [
        DashboardState(
          data: data,
          loading: false,
          refreshFailure: const PermissionFailure(),
        ),
      ],
      verify: (_) => verify(() => repository.load()).called(1),
    );

    blocTest<DashboardCubit, DashboardState>(
      'remembers how the funnel and retention are shown',
      build: build,
      act: (cubit) async {
        await pumpEventQueue();
        cubit
          ..showFunnelAs(FunnelView.table)
          ..showRetentionAs(RetentionView.curves);
      },
      skip: 2,
      expect: () => [
        DashboardState(
          data: data,
          loading: false,
          funnelView: FunnelView.table,
          retentionView: RetentionView.curves,
        ),
      ],
    );
  });

  test('before the first export there is no data', () {
    expect(const DashboardData().hasNoData, isTrue);
    expect(
      const DashboardData(
        status: DashboardStatus(state: RefreshState.noData),
        revenue: RevenueSnapshot(mrr: 1),
      ).hasNoData,
      isTrue,
    );
    expect(
      const DashboardData(status: DashboardStatus(state: RefreshState.error))
          .hasNoData,
      isFalse,
    );
  });
}
