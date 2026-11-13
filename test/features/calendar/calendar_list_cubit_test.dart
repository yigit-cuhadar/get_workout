import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/calendar/domain/calendar_month.dart';
import 'package:get_workout/features/calendar/presentation/calendar_list_cubit.dart';
import 'package:get_workout/features/cardio/domain/cardio_repository.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/cardio/domain/cardio_usecases.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/workout/domain/history_usecases.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../programs/fixtures.dart';
import '../workout/fixtures.dart' show workout;

class MockAuthRepository extends Mock implements AuthRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockCardioRepository extends Mock implements CardioRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

CalendarDate d(int year, int month, int day) => CalendarDate(year, month, day);

void main() {
  const alice = AuthUser(id: 'u1', isAnonymous: true);
  const bob = AuthUser(id: 'u2', isAnonymous: true);
  const c1 = HistoryCursor('c1');
  const c2 = HistoryCursor('c2');
  // Wednesday 11 November 2026.
  final now = DateTime(2026, 11, 11, 20);
  final upperLower = program(id: 'p1');
  final active = ActiveProgram(
    programId: 'p1',
    weekdays: const [5],
    nextDayIndex: 0,
    nextDate: d(2026, 11, 13),
    startedAt: DateTime(2026, 11, 2),
  );
  final run = CardioSession(
    id: 'c1',
    type: CardioType.treadmillRun,
    date: DateTime(2026, 11, 10, 7),
    duration: const Duration(minutes: 30),
  );

  late StreamController<AuthUser?> users;
  late StreamController<Failure> rejected;
  late MockWorkoutRepository repository;
  late MockCardioRepository cardio;
  late MockProgramRepository programs;

  /// The streams asked for: history pages by user, start and end, the rest
  /// by user.
  late Map<String, StreamController<HistoryPage>> pages;
  late Map<String, StreamController<List<CardioSession>>> cardioStreams;
  late Map<String, StreamController<List<Program>>> programStreams;
  late Map<String, StreamController<ActiveProgram?>> activeStreams;

  String key(String uid, HistoryCursor? after, HistoryCursor? through) =>
      '$uid ${after?.position} ${through?.position}';

  /// Workout `w<day>`, on that day of November 2026; older ids are older.
  Workout w(int day) =>
      workout('w$day', const [], startedAt: DateTime(2026, 11, day, 18));

  HistoryPage page(List<int> days, {HistoryCursor? end, bool more = false}) =>
      (workouts: [for (final day in days) w(day)], end: end, more: more);

  StreamController<T> by<T>(
    Map<String, StreamController<T>> streams,
    Invocation call,
  ) => streams.putIfAbsent(
    call.positionalArguments.first as String,
    StreamController<T>.broadcast,
  );

  setUp(() {
    users = StreamController<AuthUser?>();
    rejected = StreamController<Failure>.broadcast();
    repository = MockWorkoutRepository();
    cardio = MockCardioRepository();
    programs = MockProgramRepository();
    pages = {};
    cardioStreams = {};
    programStreams = {};
    activeStreams = {};
    when(
      () => repository.watchHistory(
        any(),
        after: any(named: 'after'),
        through: any(named: 'through'),
      ),
    ).thenAnswer(
      (call) => pages
          .putIfAbsent(
            key(
              call.positionalArguments.first as String,
              call.namedArguments[#after] as HistoryCursor?,
              call.namedArguments[#through] as HistoryCursor?,
            ),
            StreamController<HistoryPage>.broadcast,
          )
          .stream,
    );
    when(() => repository.rejectedEdits).thenAnswer((_) => rejected.stream);
    when(() => cardio.watchSessions(any()))
        .thenAnswer((call) => by(cardioStreams, call).stream);
    when(() => programs.watchPrograms(any()))
        .thenAnswer((call) => by(programStreams, call).stream);
    when(() => programs.watchActiveProgram(any()))
        .thenAnswer((call) => by(activeStreams, call).stream);
  });

  tearDown(() async {
    await users.close();
    await rejected.close();
  });

  /// Signed in as [user], with no cardio and no program unless [known] is
  /// false.
  Future<CalendarListCubit> signedIn({
    AuthUser user = alice,
    bool known = true,
  }) async {
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    final cubit = CalendarListCubit(
      firstWeekday: DateTime.monday,
      watchAuthUser: WatchAuthUser(auth),
      watchHistory: WatchHistory(repository),
      watchCardio: WatchCardioSessions(cardio),
      watchPrograms: WatchPrograms(programs),
      watchActiveProgram: WatchActiveProgram(programs),
      watchRejectedEdits: WatchRejectedWorkoutEdits(repository),
      clock: () => now,
    );
    users.add(user);
    await pumpEventQueue();
    if (known) {
      cardioStreams[user.id]!.add([]);
      programStreams[user.id]!.add([]);
      activeStreams[user.id]!.add(null);
      await pumpEventQueue();
    }
    return cubit;
  }

  Future<void> emit(String key, HistoryPage data) async {
    pages[key]!.add(data);
    await pumpEventQueue();
  }

  List<String> ids(CalendarListCubit cubit) => [
    for (final day in cubit.state.days)
      for (final entry in day.entries)
        if (entry case WorkoutEntry(:final workout)) workout.id,
  ];

  test('ready once workouts, cardio and the program are known', () async {
    final cubit = await signedIn(known: false);
    await emit('u1 null null', page([11, 9]));
    cardioStreams['u1']!.add([run]);
    programStreams['u1']!.add([upperLower]);
    await pumpEventQueue();
    expect(cubit.state.status, CalendarListStatus.loading);

    activeStreams['u1']!.add(active);
    await pumpEventQueue();
    expect(cubit.state.status, CalendarListStatus.ready);
    expect(
      [for (final day in cubit.state.days) day.date],
      // This week's planned Friday first.
      [d(2026, 11, 13), d(2026, 11, 11), d(2026, 11, 10), d(2026, 11, 9)],
    );
    expect(cubit.state.days.first.entries.single, isA<PlanEntry>());
    expect(cubit.state.days[2].entries, [CardioEntry(run)]);
    expect(cubit.state.isEmpty, isFalse);
    await cubit.close();
  });

  test('without programs it still lists what was done', () async {
    final cubit = await signedIn(known: false);
    await emit('u1 null null', page([11]));
    cardioStreams['u1']!.add([]);
    programStreams['u1']!.addError(const NetworkFailure('offline'));
    activeStreams['u1']!.addError(const NetworkFailure('offline'));
    await pumpEventQueue();
    expect(cubit.state.status, CalendarListStatus.ready);
    expect(ids(cubit), ['w11']);
    await cubit.close();
  });

  test('nothing at all is empty', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page([]));
    expect(cubit.state.status, CalendarListStatus.ready);
    expect(cubit.state.isEmpty, isTrue);
    await cubit.close();
  });

  test('more pages follow, each earlier one given its end', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page([9, 8], end: c1, more: true));
    expect(cubit.state.more, isTrue);

    cubit.loadMore();
    expect(cubit.state.loadingMore, isTrue);
    // So the list keeps a row for the spinner.
    expect(cubit.state.more, isTrue);
    expect(pages.keys, containsAll(['u1 null c1', 'u1 c1 null']));
    // Asking again while loading changes nothing.
    cubit.loadMore();
    expect(pages, hasLength(3));

    await emit('u1 c1 null', page([7], end: c2));
    expect(ids(cubit), ['w9', 'w8', 'w7']);
    expect(cubit.state.loadingMore, isFalse);
    expect(cubit.state.more, isFalse);

    // The first page, now with an end, grows with a new workout.
    await emit('u1 null c1', page([10, 9, 8], end: c1));
    expect(ids(cubit), ['w10', 'w9', 'w8', 'w7']);
    await cubit.close();
  });

  test('a workout moved between pages shows once', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page([9, 8], end: c1, more: true));
    cubit.loadMore();
    await emit('u1 c1 null', page([8, 7]));
    expect(ids(cubit), ['w9', 'w8', 'w7']);
    await cubit.close();
  });

  test('cardio older than the workouts loaded waits for them', () async {
    final cubit = await signedIn();
    final early = CardioSession(
      id: 'c2',
      type: CardioType.treadmillRun,
      date: DateTime(2026, 11, 2, 7),
      duration: const Duration(minutes: 30),
    );
    cardioStreams['u1']!.add([run, early]);
    await emit('u1 null null', page([9], end: c1, more: true));
    expect(
      [for (final day in cubit.state.days) day.date],
      [d(2026, 11, 10), d(2026, 11, 9)],
    );

    cubit.loadMore();
    await emit('u1 c1 null', page([1]));
    expect(cubit.state.days.map((day) => day.date), contains(d(2026, 11, 2)));
    await cubit.close();
  });

  test('pages past the live ones are read once', () async {
    final cubit = await signedIn();
    String? after;
    for (var i = 0; i <= CalendarListCubit.maxLivePages; i++) {
      final end = HistoryCursor('c$i');
      await emit('u1 $after null', page([10 - i], end: end, more: true));
      after = 'c$i';
      cubit.loadMore();
    }
    // Page 6 (index 5) is the first read once: it stops after its answer.
    final once = pages['u1 c4 c5']!;
    expect(once.hasListener, isTrue);
    await emit('u1 c4 c5', page([5], end: const HistoryCursor('c5')));
    expect(once.hasListener, isFalse);
    expect(pages['u1 c3 c4']!.hasListener, isTrue);
    expect(ids(cubit), ['w10', 'w9', 'w8', 'w7', 'w6', 'w5']);
    await cubit.close();
  });

  test('a date asked for loads older pages until it is covered', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page([9, 8], end: c1, more: true));

    cubit.reveal(d(2026, 11, 4));
    expect(cubit.state.loadingMore, isTrue);
    await emit('u1 c1 null', page([5, 4], end: c2, more: true));
    // Its own date is the oldest loaded: one more page.
    expect(cubit.state.loadingMore, isTrue);
    expect(pages, contains('u1 c2 null'));
    await emit('u1 c2 null', page([1]));
    expect(cubit.state.loadingMore, isFalse);
    expect(cubit.state.days.map((day) => day.date), contains(d(2026, 11, 4)));

    // A covered date without entries is listed empty, until another one.
    cubit.reveal(d(2026, 11, 6));
    final empty = cubit.state.days.firstWhere(
      (day) => day.date == d(2026, 11, 6),
    );
    expect(empty.entries, isEmpty);
    expect(cubit.state.isEmpty, isFalse);
    cubit.reveal(null);
    expect(
      cubit.state.days.map((day) => day.date),
      isNot(contains(d(2026, 11, 6))),
    );
    await cubit.close();
  });

  test('closing stops every listener', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page([9], end: c1, more: true));
    cubit.loadMore();
    await cubit.close();
    expect(pages.values.any((c) => c.hasListener), isFalse);
    expect(cardioStreams['u1']!.hasListener, isFalse);
    expect(activeStreams['u1']!.hasListener, isFalse);
  });

  test('without more nothing loads', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page([9], end: c1));
    cubit.loadMore();
    expect(pages, hasLength(1));
    await cubit.close();
  });

  test('a failure is shown and retried', () async {
    final cubit = await signedIn();
    pages['u1 null null']!.addError(const NetworkFailure());
    await pumpEventQueue();
    expect(cubit.state.status, CalendarListStatus.failure);
    expect(cubit.state.failure, isA<NetworkFailure>());
    expect(cardioStreams['u1']!.hasListener, isFalse);

    cubit.retry();
    expect(cubit.state.status, CalendarListStatus.loading);
    await pumpEventQueue();
    cardioStreams['u1']!.add([]);
    programStreams['u1']!.add([]);
    activeStreams['u1']!.add(null);
    await emit('u1 null null', page([9]));
    expect(ids(cubit), ['w9']);
    await cubit.close();
  });

  test('a cardio failure fails the list', () async {
    final cubit = await signedIn(known: false);
    cardioStreams['u1']!.addError(const NetworkFailure());
    await pumpEventQueue();
    expect(cubit.state.status, CalendarListStatus.failure);
    await cubit.close();
  });

  test('another user starts over with their own', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page([9]));
    users.add(bob);
    await pumpEventQueue();
    expect(cubit.state.status, CalendarListStatus.loading);
    expect(cubit.state.days, isEmpty);
    // The previous user's page no longer shows.
    pages['u1 null null']!.add(page([8]));
    await pumpEventQueue();
    expect(cubit.state.days, isEmpty);
    cardioStreams['u2']!.add([]);
    programStreams['u2']!.add([]);
    activeStreams['u2']!.add(null);
    await emit('u2 null null', page([5]));
    expect(ids(cubit), ['w5']);
    await cubit.close();
  });

  test('a refused edit is reported once', () async {
    final cubit = await signedIn();
    rejected.add(const PermissionFailure());
    await pumpEventQueue();
    expect(cubit.state.writeRejected, isTrue);
    // It survives the list loading.
    await emit('u1 null null', page([9]));
    expect(cubit.state.writeRejected, isTrue);
    cubit.rejectionShown();
    expect(cubit.state.writeRejected, isFalse);
    await cubit.close();
  });
}
