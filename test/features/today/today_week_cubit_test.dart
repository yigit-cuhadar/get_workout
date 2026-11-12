import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/calendar/domain/calendar_month.dart';
import 'package:get_workout/features/cardio/domain/cardio_repository.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/cardio/domain/cardio_usecases.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/today/presentation/today_week_cubit.dart';
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
  // Friday 13 November 2026; the Sunday week runs 8 to 14 November.
  var now = DateTime(2026, 11, 13, 12);
  final sunday = d(2026, 11, 8);
  final upperLower = program(id: 'p1');
  // Monday and Thursday. Monday's day 0 was done; Thursday's day 1 was
  // missed, so it comes again on Monday 16.
  final active = ActiveProgram(
    programId: 'p1',
    weekdays: const [1, 4],
    nextDayIndex: 1,
    nextDate: d(2026, 11, 12),
    startedAt: DateTime(2026, 11, 2),
  );
  final upper = workout(
    'w1',
    const [],
    startedAt: DateTime(2026, 11, 9, 7),
    programId: 'p1',
    dayIndex: 0,
  );
  final run = CardioSession(
    id: 'c1',
    type: CardioType.treadmillRun,
    date: DateTime(2026, 11, 13, 7),
    duration: const Duration(minutes: 30),
  );

  late StreamController<AuthUser?> users;
  late MockWorkoutRepository workouts;
  late MockCardioRepository cardio;
  late MockProgramRepository programs;

  /// The streams asked for, by user and first date.
  late Map<String, StreamController<List<Workout>>> workoutStreams;
  late Map<String, StreamController<List<CardioSession>>> cardioStreams;
  late Map<String, StreamController<List<Program>>> programStreams;
  late Map<String, StreamController<ActiveProgram?>> activeStreams;

  String key(Invocation call) =>
      '${call.positionalArguments.first} ${call.namedArguments[#from]}';

  setUpAll(() => registerFallbackValue(d(2026, 1, 1)));

  setUp(() {
    now = DateTime(2026, 11, 13, 12);
    users = StreamController<AuthUser?>.broadcast();
    workouts = MockWorkoutRepository();
    cardio = MockCardioRepository();
    programs = MockProgramRepository();
    workoutStreams = {};
    cardioStreams = {};
    programStreams = {};
    activeStreams = {};
    when(
      () => workouts.watchWorkoutsBetween(
        any(),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer(
      (call) => workoutStreams
          .putIfAbsent(key(call), StreamController<List<Workout>>.broadcast)
          .stream,
    );
    when(
      () => cardio.watchSessionsBetween(
        any(),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer(
      (call) => cardioStreams
          .putIfAbsent(
            key(call),
            StreamController<List<CardioSession>>.broadcast,
          )
          .stream,
    );
    when(() => programs.watchPrograms(any())).thenAnswer(
      (call) => programStreams
          .putIfAbsent(
            call.positionalArguments.first as String,
            StreamController<List<Program>>.broadcast,
          )
          .stream,
    );
    when(() => programs.watchActiveProgram(any())).thenAnswer(
      (call) => activeStreams
          .putIfAbsent(
            call.positionalArguments.first as String,
            StreamController<ActiveProgram?>.broadcast,
          )
          .stream,
    );
  });

  tearDown(() => users.close());

  TodayWeekCubit build({int firstWeekday = DateTime.sunday}) {
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    return TodayWeekCubit(
      firstWeekday: firstWeekday,
      watchAuthUser: WatchAuthUser(auth),
      watchWorkouts: WatchWorkoutsBetween(workouts),
      watchCardio: WatchCardioBetween(cardio),
      watchPrograms: WatchPrograms(programs),
      watchActiveProgram: WatchActiveProgram(programs),
      clock: () => now,
    );
  }

  /// Signs [user] in and delivers their week.
  Future<void> load(
    AuthUser user, {
    CalendarDate? from,
    List<Workout> done = const [],
    List<CardioSession> sessions = const [],
    ActiveProgram? activeProgram,
  }) async {
    users.add(user);
    await pumpEventQueue();
    final week = '${user.id} ${from ?? sunday}';
    workoutStreams[week]!.add(done);
    cardioStreams[week]!.add(sessions);
    programStreams[user.id]!.add([upperLower]);
    activeStreams[user.id]!.add(activeProgram);
    await pumpEventQueue();
  }

  List<CalendarMark> marksOn(TodayWeekCubit cubit, CalendarDate date) =>
      calendarMarks(cubit.state.entriesOn(date));

  test('starts loading on the locale\'s week, today included', () {
    final sundays = build().state;
    expect(sundays.status, TodayWeekStatus.loading);
    expect(sundays.today, d(2026, 11, 13));
    expect(sundays.days, [for (var i = 0; i < 7; i++) sunday.addDays(i)]);
    expect(
      build(firstWeekday: DateTime.monday).state.days.first,
      d(2026, 11, 9),
    );
  });

  blocTest<TodayWeekCubit, TodayWeekState>(
    'marks days done, planned and missed from the shared plan',
    build: build,
    act: (_) =>
        load(alice, done: [upper], sessions: [run], activeProgram: active),
    verify: (cubit) {
      expect(cubit.state.status, TodayWeekStatus.ready);
      verify(
        () => workouts.watchWorkoutsBetween(
          'u1',
          from: sunday,
          to: d(2026, 11, 14),
        ),
      ).called(1);
      // The program day done shows once, as its workout.
      expect(marksOn(cubit, d(2026, 11, 9)), [CalendarMark.workout]);
      expect(marksOn(cubit, d(2026, 11, 12)), [CalendarMark.missed]);
      expect(marksOn(cubit, d(2026, 11, 13)), [CalendarMark.cardio]);
      expect(marksOn(cubit, d(2026, 11, 8)), isEmpty);
      expect(marksOn(cubit, d(2026, 11, 14)), isEmpty);
    },
  );

  blocTest<TodayWeekCubit, TodayWeekState>(
    'plans the next day on its date',
    build: () {
      // Wednesday, before Thursday's day.
      now = DateTime(2026, 11, 11, 12);
      return build();
    },
    act: (_) => load(alice, activeProgram: active),
    verify: (cubit) {
      expect(cubit.state.today, d(2026, 11, 11));
      expect(marksOn(cubit, d(2026, 11, 12)), [CalendarMark.planned]);
    },
  );

  blocTest<TodayWeekCubit, TodayWeekState>(
    'without an active program only what was done shows',
    build: build,
    act: (_) => load(alice, done: [upper]),
    verify: (cubit) {
      expect(marksOn(cubit, d(2026, 11, 9)), [CalendarMark.workout]);
      expect(cubit.state.entries.values.expand(calendarMarks), [
        CalendarMark.workout,
      ]);
    },
  );

  blocTest<TodayWeekCubit, TodayWeekState>(
    'programs that cannot be read still leave what was done',
    build: build,
    act: (_) async {
      users.add(alice);
      await pumpEventQueue();
      workoutStreams['u1 $sunday']!.add([upper]);
      cardioStreams['u1 $sunday']!.add(const []);
      programStreams['u1']!.addError(const NetworkFailure('offline'));
      activeStreams['u1']!.addError(const NetworkFailure('offline'));
      await pumpEventQueue();
    },
    verify: (cubit) {
      expect(cubit.state.status, TodayWeekStatus.ready);
      expect(marksOn(cubit, d(2026, 11, 9)), [CalendarMark.workout]);
    },
  );

  blocTest<TodayWeekCubit, TodayWeekState>(
    'fails when the workouts cannot be read, and retries',
    build: build,
    act: (cubit) async {
      users.add(alice);
      await pumpEventQueue();
      workoutStreams['u1 $sunday']!.addError(const NetworkFailure('offline'));
      await pumpEventQueue();
      expect(cubit.state.status, TodayWeekStatus.failure);
      expect(cubit.state.failure, const NetworkFailure('offline'));
      cubit.retry();
      await pumpEventQueue();
      workoutStreams['u1 $sunday']!.add([upper]);
      cardioStreams['u1 $sunday']!.add(const []);
      programStreams['u1']!.add([upperLower]);
      activeStreams['u1']!.add(null);
      await pumpEventQueue();
    },
    verify: (cubit) {
      expect(cubit.state.status, TodayWeekStatus.ready);
      expect(marksOn(cubit, d(2026, 11, 9)), [CalendarMark.workout]);
    },
  );

  blocTest<TodayWeekCubit, TodayWeekState>(
    'a user change drops the previous user\'s week',
    build: build,
    act: (cubit) async {
      await load(alice, done: [upper], activeProgram: active);
      users.add(bob);
      await pumpEventQueue();
      expect(cubit.state.status, TodayWeekStatus.loading);
      expect(cubit.state.entries, isEmpty);
      // Alice's streams no longer count.
      workoutStreams['u1 $sunday']!.add([upper]);
      await pumpEventQueue();
      expect(cubit.state.status, TodayWeekStatus.loading);
      await load(bob);
    },
    verify: (cubit) {
      expect(cubit.state.status, TodayWeekStatus.ready);
      expect(cubit.state.entries, isEmpty);
    },
  );

  blocTest<TodayWeekCubit, TodayWeekState>(
    'a snapshot after the week ended follows the new week',
    build: build,
    act: (cubit) async {
      await load(alice, done: [upper]);
      // Saturday night turns into Sunday with the app in front.
      now = DateTime(2026, 11, 15, 0, 5);
      workoutStreams['u1 $sunday']!.add([upper]);
      await pumpEventQueue();
      expect(cubit.state.status, TodayWeekStatus.loading);
      expect(cubit.state.days.first, d(2026, 11, 15));
      await load(alice, from: d(2026, 11, 15));
    },
    verify: (cubit) {
      expect(cubit.state.status, TodayWeekStatus.ready);
      expect(cubit.state.today, d(2026, 11, 15));
      expect(cubit.state.days, [
        for (var i = 0; i < 7; i++) d(2026, 11, 15).addDays(i),
      ]);
      expect(cubit.state.entries, isEmpty);
    },
  );

  blocTest<TodayWeekCubit, TodayWeekState>(
    'moves to the next week after midnight on its last day',
    build: build,
    act: (cubit) async {
      await load(alice, done: [upper]);
      now = DateTime(2026, 11, 14, 23);
      cubit.refreshNow();
      expect(cubit.state.today, d(2026, 11, 14));
      expect(cubit.state.days.first, sunday);
      now = DateTime(2026, 11, 15, 1);
      cubit.refreshNow();
      await pumpEventQueue();
      expect(cubit.state.status, TodayWeekStatus.loading);
      await load(alice, from: d(2026, 11, 15));
    },
    verify: (cubit) {
      expect(cubit.state.today, d(2026, 11, 15));
      expect(cubit.state.days.first, d(2026, 11, 15));
      expect(cubit.state.entries, isEmpty);
    },
  );
}
