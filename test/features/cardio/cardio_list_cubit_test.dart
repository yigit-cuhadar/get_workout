import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/cardio/domain/cardio_repository.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/cardio/domain/cardio_usecases.dart';
import 'package:get_workout/features/cardio/domain/cardio_week.dart';
import 'package:get_workout/features/cardio/presentation/cardio_list_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockCardioRepository extends Mock implements CardioRepository {}

void main() {
  const guest = AuthUser(id: 'g1', isAnonymous: true);
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  var now = DateTime(2026, 11, 11, 12);
  final guestRun = CardioSession(
    id: 'a',
    type: CardioType.outdoorRun,
    date: DateTime(2026, 11, 10, 7),
    duration: const Duration(minutes: 30),
  );
  final memberRide = CardioSession(
    id: 'b',
    type: CardioType.outdoorCycle,
    date: DateTime(2026, 11, 2, 9),
    duration: const Duration(minutes: 60),
  );

  late MockAuthRepository auth;
  late MockCardioRepository cardio;
  late StreamController<AuthUser?> users;
  late Map<String, StreamController<List<CardioSession>>> stored;
  late StreamController<Failure> rejected;

  setUp(() {
    auth = MockAuthRepository();
    cardio = MockCardioRepository();
    users = StreamController<AuthUser?>();
    stored = {};
    rejected = StreamController<Failure>.broadcast();
    now = DateTime(2026, 11, 11, 12);
    when(() => cardio.rejectedWrites).thenAnswer((_) => rejected.stream);
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => cardio.watchSessions(any())).thenAnswer(
      (call) => stored
          .putIfAbsent(
            call.positionalArguments.first as String,
            StreamController<List<CardioSession>>.new,
          )
          .stream,
    );
  });

  CardioListCubit build() => CardioListCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchSessions: WatchCardioSessions(cardio),
    watchRejectedWrites: WatchRejectedCardioWrites(cardio),
    clock: () => now,
  );

  CardioListState ready(List<CardioSession> sessions) => CardioListState(
    status: CardioListStatus.ready,
    sessions: sessions,
    weeks: groupByWeek(sessions, DateTime.monday),
    chart: lastWeeks(sessions, DateTime.monday, now: now),
  );

  test('starts loading', () {
    expect(build().state, const CardioListState());
  });

  blocTest<CardioListCubit, CardioListState>(
    'shows the sessions with their weeks and the 12-week chart',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add([guestRun, memberRide]);
    },
    expect: () => [
      ready([guestRun, memberRide]),
    ],
    verify: (cubit) {
      expect(cubit.state.weeks, hasLength(2));
      expect(cubit.state.chart, hasLength(12));
      expect(cubit.state.chart.last.duration, const Duration(minutes: 30));
    },
  );

  blocTest<CardioListCubit, CardioListState>(
    'follows whoever is signed in and resets at once on a user change',
    build: build,
    act: (_) async {
      users.add(guest);
      await pumpEventQueue();
      stored['g1']!.add([guestRun]);
      await pumpEventQueue();
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add([memberRide]);
      await pumpEventQueue();
      // The previous user's stream is no longer followed.
      stored['g1']!.add([guestRun, guestRun]);
    },
    expect: () => [
      ready([guestRun]),
      const CardioListState(),
      ready([memberRide]),
    ],
    verify: (_) => expect(stored['g1']!.hasListener, isFalse),
  );

  blocTest<CardioListCubit, CardioListState>(
    'signing out clears the list',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add([memberRide]);
      await pumpEventQueue();
      users.add(null);
    },
    expect: () => [
      ready([memberRide]),
      const CardioListState(),
    ],
  );

  blocTest<CardioListCubit, CardioListState>(
    'a profile change of the same user keeps the subscription',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      users.add(const AuthUser(id: 'u1', email: 'a@b.co', displayName: 'A'));
    },
    verify: (_) => verify(() => cardio.watchSessions('u1')).called(1),
  );

  const failure = PermissionFailure();

  blocTest<CardioListCubit, CardioListState>(
    'a stream error shows a failure, and retry subscribes again',
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.addError(failure);
      await pumpEventQueue();
      stored.remove('u1');
      cubit.retry();
      await pumpEventQueue();
      stored['u1']!.add([memberRide]);
    },
    expect: () => [
      const CardioListState(status: CardioListStatus.failure, failure: failure),
      const CardioListState(),
      ready([memberRide]),
    ],
    verify: (_) => verify(() => cardio.watchSessions('u1')).called(2),
  );

  blocTest<CardioListCubit, CardioListState>(
    'a rejected write is reported once, until shown',
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add([memberRide]);
      await pumpEventQueue();
      rejected
        ..add(const PermissionFailure())
        ..add(const PermissionFailure());
      await pumpEventQueue();
      cubit.rejectionShown();
    },
    expect: () => [
      ready([memberRide]),
      ready([memberRide]).copyWith(writeRejected: true),
      ready([memberRide]),
    ],
  );

  blocTest<CardioListCubit, CardioListState>(
    'a rejection survives a user change until it is shown',
    build: build,
    act: (_) async {
      rejected.add(const PermissionFailure());
      await pumpEventQueue();
      users.add(member);
    },
    verify: (cubit) => expect(cubit.state.writeRejected, isTrue),
  );

  blocTest<CardioListCubit, CardioListState>(
    'refreshNow moves the chart to the current week without a snapshot',
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add([guestRun]);
      await pumpEventQueue();
      // A week later, guestRun's week is no longer the current one.
      now = now.add(const Duration(days: 7));
      cubit.refreshNow();
    },
    skip: 1,
    expect: () => [
      isA<CardioListState>()
          .having(
            (s) => s.chart.last.start,
            'current week',
            DateTime(2026, 11, 16),
          )
          .having((s) => s.chart[10].sessions, 'last week', [guestRun]),
    ],
  );

  blocTest<CardioListCubit, CardioListState>(
    'refreshNow while loading does nothing',
    build: build,
    act: (cubit) => cubit.refreshNow(),
    expect: () => const <CardioListState>[],
  );

  group('the first weekday', () {
    final sundayWalk = CardioSession(
      id: 'c',
      type: CardioType.outdoorRun,
      date: DateTime(2026, 11, 8, 9),
      duration: const Duration(minutes: 20),
    );
    final sessions = [guestRun, sundayWalk, memberRide];

    CardioListState readyFrom(int firstWeekday) => CardioListState(
      status: CardioListStatus.ready,
      sessions: sessions,
      weeks: groupByWeek(sessions, firstWeekday),
      chart: lastWeeks(sessions, firstWeekday, now: now),
    );

    blocTest<CardioListCubit, CardioListState>(
      'regroups the weeks and the chart when it changes',
      build: build,
      act: (cubit) async {
        users.add(member);
        await pumpEventQueue();
        stored['u1']!.add(sessions);
        await pumpEventQueue();
        cubit.changeFirstWeekday(DateTime.monday);
        cubit.changeFirstWeekday(DateTime.sunday);
      },
      expect: () => [readyFrom(DateTime.monday), readyFrom(DateTime.sunday)],
      verify: (cubit) {
        // Sunday 8 November now opens this week instead of ending the last.
        expect(cubit.state.weeks.first.start, DateTime(2026, 11, 8));
        expect(cubit.state.weeks.first.sessions, [guestRun, sundayWalk]);
        expect(cubit.state.chart.last.duration, const Duration(minutes: 50));
      },
    );

    blocTest<CardioListCubit, CardioListState>(
      'given before the sessions arrive, groups them by it',
      build: build,
      act: (cubit) async {
        cubit.changeFirstWeekday(DateTime.sunday);
        users.add(member);
        await pumpEventQueue();
        stored['u1']!.add(sessions);
      },
      expect: () => [readyFrom(DateTime.sunday)],
    );
  });
}
