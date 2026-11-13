import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/calendar/domain/calendar_days.dart';
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
import 'package:get_workout/features/programs/domain/program_schedule.dart';
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
  // Wednesday 11 November 2026; the week runs from the 9th to the 15th.
  final now = DateTime(2026, 11, 11, 20);
  final upperLower = program(id: 'p1');
  final active = ActiveProgram(
    programId: 'p1',
    weekdays: const [5],
    nextDayIndex: 0,
    nextDate: d(2026, 11, 13),
    startedAt: DateTime(2026, 11, 2),
  );
  CardioSession session(String id, DateTime date) => CardioSession(
    id: id,
    type: CardioType.treadmillRun,
    date: date,
    duration: const Duration(minutes: 30),
  );
  final run = session('c1', DateTime(2026, 11, 10, 7));

  late StreamController<AuthUser?> users;
  late StreamController<Failure> rejected;
  late MockWorkoutRepository repository;
  late MockCardioRepository cardio;
  late MockProgramRepository programs;

  /// The streams asked for: history pages by user, start and end; ranges
  /// of dates by user, first and last date; the rest by user.
  late Map<String, StreamController<HistoryPage>> pages;
  late Map<String, StreamController<List<Workout>>> workoutRanges;
  late Map<String, StreamController<List<CardioSession>>> cardioRanges;
  late Map<String, StreamController<List<Program>>> programStreams;
  late Map<String, StreamController<ActiveProgram?>> activeStreams;

  /// What each cardio range answers, empty unless set; see [emit].
  late Map<String, List<CardioSession>> cardioOf;
  late Set<String> cardioAnswered;

  String key(String uid, HistoryCursor? after, HistoryCursor? through) =>
      '$uid ${after?.position} ${through?.position}';

  String rangeKey(Invocation call) =>
      '${call.positionalArguments.first} ${call.namedArguments[#from]} '
      '${call.namedArguments[#to]}';

  /// Workout `w<day>`, on that day of November 2026; older ids are older.
  Workout w(int day) =>
      workout('w$day', const [], startedAt: DateTime(2026, 11, day, 18));

  HistoryPage page(List<int> days, {HistoryCursor? end, bool more = false}) =>
      (workouts: [for (final day in days) w(day)], end: end, more: more);

  StreamController<T> byUser<T>(
    Map<String, StreamController<T>> streams,
    Invocation call,
  ) => streams.putIfAbsent(
    call.positionalArguments.first as String,
    StreamController<T>.broadcast,
  );

  setUpAll(() => registerFallbackValue(d(2026, 1, 1)));

  setUp(() {
    users = StreamController<AuthUser?>();
    rejected = StreamController<Failure>.broadcast();
    repository = MockWorkoutRepository();
    cardio = MockCardioRepository();
    programs = MockProgramRepository();
    pages = {};
    workoutRanges = {};
    cardioRanges = {};
    programStreams = {};
    activeStreams = {};
    cardioOf = {};
    cardioAnswered = {};
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
    when(
      () => repository.watchWorkoutsBetween(
        any(),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer(
      (call) => workoutRanges
          .putIfAbsent(rangeKey(call), StreamController.broadcast)
          .stream,
    );
    when(() => repository.rejectedEdits).thenAnswer((_) => rejected.stream);
    when(
      () => cardio.watchSessionsBetween(
        any(),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer(
      (call) => cardioRanges
          .putIfAbsent(rangeKey(call), StreamController.broadcast)
          .stream,
    );
    when(() => programs.watchPrograms(any()))
        .thenAnswer((call) => byUser(programStreams, call).stream);
    when(() => programs.watchActiveProgram(any()))
        .thenAnswer((call) => byUser(activeStreams, call).stream);
  });

  tearDown(() async {
    await users.close();
    await rejected.close();
  });

  /// Answers the cardio ranges asked for since the last call.
  Future<void> answerCardio() async {
    for (final MapEntry(:key, :value) in cardioRanges.entries.toList()) {
      if (cardioAnswered.add(key)) value.add(cardioOf[key] ?? const []);
    }
    await pumpEventQueue();
  }

  Future<void> answerUser(String uid, {ActiveProgram? activeProgram}) async {
    programStreams[uid]!.add([upperLower]);
    activeStreams[uid]!.add(activeProgram);
    await pumpEventQueue();
  }

  /// Signed in as [user], with no active program unless [known] is false.
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
      watchWorkouts: WatchWorkoutsBetween(repository),
      watchCardio: WatchCardioBetween(cardio),
      watchPrograms: WatchPrograms(programs),
      watchActiveProgram: WatchActiveProgram(programs),
      watchRejectedEdits: WatchRejectedWorkoutEdits(repository),
      clock: () => now,
    );
    users.add(user);
    await pumpEventQueue();
    if (known) await answerUser(user.id);
    return cubit;
  }

  /// Answers history page [key] with [data], then the cardio of the dates
  /// it brought in.
  Future<void> emit(String key, HistoryPage data) async {
    pages[key]!.add(data);
    await pumpEventQueue();
    await answerCardio();
  }

  List<String> ids(CalendarListCubit cubit) => [
    for (final day in cubit.state.days)
      for (final entry in day.entries)
        if (entry case WorkoutEntry(:final workout)) workout.id,
  ];

  List<CalendarDate> dates(CalendarListCubit cubit) => [
    for (final day in cubit.state.days) day.date,
  ];

  test('ready once workouts, the program and the cardio of the dates '
      'listed are known', () async {
    final cubit = await signedIn(known: false);
    pages['u1 null null']!.add(page([11, 9]));
    programStreams['u1']!.add([upperLower]);
    await pumpEventQueue();
    // Asked only once everything else is known.
    expect(cardioRanges, isEmpty);
    activeStreams['u1']!.add(active);
    await pumpEventQueue();
    expect(cubit.state.status, CalendarListStatus.loading);
    // This week, back to the oldest workout, which is in it.
    expect(cardioRanges.keys, ['u1 2026-11-09 2026-11-15']);

    cardioOf['u1 2026-11-09 2026-11-15'] = [run];
    await answerCardio();
    expect(cubit.state.status, CalendarListStatus.ready);
    expect(
      dates(cubit),
      // This week's planned Friday first.
      [d(2026, 11, 13), d(2026, 11, 11), d(2026, 11, 10), d(2026, 11, 9)],
    );
    expect(cubit.state.days.first.entries.single, isA<PlanEntry>());
    expect(cubit.state.days[2].entries, [CardioEntry(run)]);
    expect(cubit.state.isEmpty, isFalse);
    verifyNever(() => cardio.watchSessions(any()));
    await cubit.close();
  });

  test('without programs it still lists what was done', () async {
    final cubit = await signedIn(known: false);
    programStreams['u1']!.addError(const NetworkFailure('offline'));
    activeStreams['u1']!.addError(const NetworkFailure('offline'));
    await emit('u1 null null', page([11]));
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

  test('each older page reads the cardio of its own dates only', () async {
    final cubit = await signedIn();
    final early = session('c2', DateTime(2026, 11, 2, 7));
    cardioOf['u1 2026-11-08 2026-11-15'] = [run];
    cardioOf['u1 2026-11-02 2026-11-07'] = [early];
    await emit('u1 null null', page([9, 8], end: c1, more: true));
    // From the oldest workout's date, which shows only its workouts.
    expect(dates(cubit), [d(2026, 11, 10), d(2026, 11, 9), d(2026, 11, 8)]);

    cubit.loadMore();
    pages['u1 c1 null']!.add(page([4, 2], end: c2, more: true));
    await pumpEventQueue();
    expect(cardioRanges.keys, [
      'u1 2026-11-08 2026-11-15',
      'u1 2026-11-02 2026-11-07',
    ]);
    // Until that cardio is known, the spinner stays.
    expect(cubit.state.loadingMore, isTrue);
    await answerCardio();
    expect(cubit.state.loadingMore, isFalse);
    // The 2nd is the oldest workout's date: its run waits.
    expect(dates(cubit), contains(d(2026, 11, 2)));
    expect(cubit.state.days.last.entries, [WorkoutEntry(w(2))]);

    cubit.loadMore();
    await emit('u1 c2 null', page([1]));
    expect(cubit.state.days.last.date, d(2026, 11, 1));
    expect(
      cubit.state.days.firstWhere((day) => day.date == d(2026, 11, 2)).entries,
      [WorkoutEntry(w(2)), CardioEntry(early)],
    );
    // Each range read once.
    verify(
      () => cardio.watchSessionsBetween(
        'u1',
        from: d(2026, 11, 2),
        to: d(2026, 11, 7),
      ),
    ).called(1);
    expect(cardioRanges.keys, hasLength(3));
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
    // Page 6 (index 5) is the first read once: it stops after its answer
    // and, when the next one loads, is not read again with its end.
    expect(pages['u1 c4 null']!.hasListener, isFalse);
    expect(pages, isNot(contains('u1 c4 c5')));
    expect(pages['u1 c3 c4']!.hasListener, isTrue);
    await emit('u1 c5 null', page([4], end: const HistoryCursor('c6')));
    expect(pages['u1 c5 null']!.hasListener, isFalse);
    expect(ids(cubit), ['w10', 'w9', 'w8', 'w7', 'w6', 'w5', 'w4']);
    await cubit.close();
  });

  test('an older date asked for is read on its own, no page more', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page([9, 8], end: c1, more: true));

    cubit.reveal(d(2026, 11, 1));
    expect(cubit.state.pinned, CalendarDay(d(2026, 11, 1), const []));
    expect(cubit.state.pinnedLoading, isTrue);
    expect(pages, hasLength(1));
    expect(workoutRanges.keys, ['u1 2026-11-01 2026-11-01']);

    workoutRanges['u1 2026-11-01 2026-11-01']!.add([w(1)]);
    await answerCardio();
    expect(cubit.state.pinnedLoading, isFalse);
    expect(
      cubit.state.pinned,
      CalendarDay(d(2026, 11, 1), [WorkoutEntry(w(1))]),
    );
    // The list itself is as it was.
    expect(ids(cubit), ['w9', 'w8']);

    // Once the list shows it, in place instead.
    cubit.loadMore();
    await emit('u1 c1 null', page([1]));
    expect(cubit.state.pinned, isNull);
    expect(workoutRanges['u1 2026-11-01 2026-11-01']!.hasListener, isFalse);
    expect(ids(cubit), ['w9', 'w8', 'w1']);
    await cubit.close();
  });

  test('a later date asked for shows on its own, and goes', () async {
    final cubit = await signedIn(known: false);
    await answerUser('u1', activeProgram: active);
    await emit('u1 null null', page([9]));

    cubit.reveal(d(2026, 11, 20));
    workoutRanges['u1 2026-11-20 2026-11-20']!.add([]);
    await answerCardio();
    expect(
      cubit.state.pinned,
      CalendarDay(d(2026, 11, 20), [
        PlanEntry(
          upperLower,
          PlannedDay(
            date: d(2026, 11, 20),
            dayIndex: 1,
            status: PlannedStatus.planned,
          ),
        ),
      ]),
    );
    // The list still ends with this week.
    expect(dates(cubit), [d(2026, 11, 13), d(2026, 11, 9)]);

    cubit.reveal(null);
    expect(cubit.state.pinned, isNull);
    expect(workoutRanges['u1 2026-11-20 2026-11-20']!.hasListener, isFalse);
    await cubit.close();
  });

  test('a listed date asked for shows in place, even empty', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page([11, 9]));
    cubit.reveal(d(2026, 11, 10));
    expect(cubit.state.pinned, isNull);
    expect(
      cubit.state.days.firstWhere((day) => day.date == d(2026, 11, 10)).entries,
      isEmpty,
    );
    cubit.reveal(null);
    expect(dates(cubit), isNot(contains(d(2026, 11, 10))));
    await cubit.close();
  });

  test('closing stops every listener', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page([9], end: c1, more: true));
    cubit
      ..loadMore()
      ..reveal(d(2026, 10, 1));
    await pumpEventQueue();
    await cubit.close();
    for (final streams in [
      pages,
      workoutRanges,
      cardioRanges,
      programStreams,
      activeStreams,
    ]) {
      expect(streams.values.any((c) => c.hasListener), isFalse);
    }
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
    expect(programStreams['u1']!.hasListener, isFalse);

    cubit.retry();
    expect(cubit.state.status, CalendarListStatus.loading);
    await pumpEventQueue();
    await answerUser('u1');
    cardioAnswered.clear();
    await emit('u1 null null', page([9]));
    expect(ids(cubit), ['w9']);
    await cubit.close();
  });

  test('a cardio failure fails the list', () async {
    final cubit = await signedIn();
    pages['u1 null null']!.add(page([9]));
    await pumpEventQueue();
    cardioRanges.values.single.addError(const NetworkFailure());
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
    await answerUser('u2');
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
