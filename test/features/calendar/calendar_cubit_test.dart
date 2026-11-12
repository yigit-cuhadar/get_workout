import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/calendar/domain/calendar_month.dart';
import 'package:get_workout/features/calendar/presentation/calendar_cubit.dart';
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
  // Wednesday 11 November 2026.
  final now = DateTime(2026, 11, 11, 12);
  final today = d(2026, 11, 11);
  final upperLower = program(id: 'p1');
  final active = ActiveProgram(
    programId: 'p1',
    weekdays: const [3],
    nextDayIndex: 0,
    nextDate: d(2026, 11, 18),
    startedAt: DateTime(2026, 11, 2),
  );
  final legs = workout('w1', const [], startedAt: DateTime(2026, 11, 11, 7));
  final run = CardioSession(
    id: 'c1',
    type: CardioType.treadmillRun,
    date: DateTime(2026, 11, 11, 18),
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
    users = StreamController<AuthUser?>();
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
            StreamController<List<Program>>.new,
          )
          .stream,
    );
    when(() => programs.watchActiveProgram(any())).thenAnswer(
      (call) => activeStreams
          .putIfAbsent(
            call.positionalArguments.first as String,
            StreamController<ActiveProgram?>.new,
          )
          .stream,
    );
  });

  tearDown(() => users.close());

  CalendarCubit build() {
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    return CalendarCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchWorkouts: WatchWorkoutsBetween(workouts),
      watchCardio: WatchCardioBetween(cardio),
      watchPrograms: WatchPrograms(programs),
      watchActiveProgram: WatchActiveProgram(programs),
      clock: () => now,
    );
  }

  Future<void> signIn(AuthUser user) async {
    users.add(user);
    await pumpEventQueue();
  }

  /// November 2026 loads from 26 October.
  const november = 'u1 2026-10-26';

  Future<void> deliver({
    String month = november,
    String uid = 'u1',
    List<Workout>? done,
    List<CardioSession>? sessions,
    ActiveProgram? activeProgram,
  }) async {
    workoutStreams[month]!.add(done ?? [legs]);
    cardioStreams[month]!.add(sessions ?? [run]);
    programStreams[uid]?.add([upperLower]);
    activeStreams[uid]?.add(activeProgram);
    await pumpEventQueue();
  }

  test('starts on this month, today selected, loading', () {
    final cubit = build();
    expect(cubit.state.month, d(2026, 11, 1));
    expect(cubit.state.selected, today);
    expect(cubit.state.today, today);
    expect(cubit.state.status, CalendarStatus.loading);
    unawaited(cubit.close());
  });

  test('loads the dates the month shows', () async {
    final cubit = build();
    await signIn(alice);
    verify(
      () => workouts.watchWorkoutsBetween(
        'u1',
        from: d(2026, 10, 26),
        to: d(2026, 12, 6),
      ),
    ).called(1);
    verify(
      () => cardio.watchSessionsBetween(
        'u1',
        from: d(2026, 10, 26),
        to: d(2026, 12, 6),
      ),
    ).called(1);
    await cubit.close();
  });

  test('is ready once everything is known, with the plan', () async {
    final cubit = build();
    await signIn(alice);
    workoutStreams[november]!.add([legs]);
    cardioStreams[november]!.add([run]);
    programStreams['u1']!.add([upperLower]);
    await pumpEventQueue();
    expect(cubit.state.status, CalendarStatus.loading);

    activeStreams['u1']!.add(active);
    await pumpEventQueue();
    expect(cubit.state.status, CalendarStatus.ready);
    expect(cubit.state.entriesOn(today), [
      WorkoutEntry(legs),
      CardioEntry(run),
    ]);
    expect(cubit.state.entriesOn(d(2026, 11, 18)), [
      PlanEntry(
        upperLower,
        PlannedDay(
          date: d(2026, 11, 18),
          dayIndex: 0,
          status: PlannedStatus.planned,
        ),
      ),
    ]);
    expect(cubit.state.entriesOn(d(2026, 12, 2)), hasLength(1));
    await cubit.close();
  });

  test('follows changes of the month', () async {
    final cubit = build();
    await signIn(alice);
    await deliver();
    workoutStreams[november]!.add([]);
    await pumpEventQueue();
    expect(cubit.state.entriesOn(today), [CardioEntry(run)]);
    await cubit.close();
  });

  test('another month: followed instead, its first day selected', () async {
    final cubit = build();
    await signIn(alice);
    await deliver();

    cubit.showMonth(1);
    expect(cubit.state.month, d(2026, 12, 1));
    expect(cubit.state.selected, d(2026, 12, 1));
    expect(cubit.state.status, CalendarStatus.loading);
    expect(cubit.state.entries, isEmpty);
    await pumpEventQueue();
    // November's streams are left.
    expect(workoutStreams[november]!.hasListener, isFalse);
    expect(cardioStreams[november]!.hasListener, isFalse);

    // December 2026 loads from 25 November, so its first week has the end
    // of November.
    final lastOfNovember = workout(
      'w2',
      const [],
      startedAt: DateTime(2026, 11, 30, 18),
    );
    await deliver(month: 'u1 2026-11-25', done: [lastOfNovember], sessions: []);
    expect(cubit.state.status, CalendarStatus.ready);
    expect(cubit.state.entriesOn(d(2026, 11, 30)), [
      WorkoutEntry(lastOfNovember),
    ]);

    cubit.showMonth(-1);
    expect(cubit.state.selected, today);
    await cubit.close();
  });

  test('selecting a date lists it; one of another month shows it', () async {
    final cubit = build();
    await signIn(alice);
    await deliver();

    cubit.select(d(2026, 11, 3));
    expect(cubit.state.selected, d(2026, 11, 3));
    expect(cubit.state.status, CalendarStatus.ready);

    cubit.select(d(2026, 10, 30));
    expect(cubit.state.month, d(2026, 10, 1));
    expect(cubit.state.selected, d(2026, 10, 30));
    expect(cubit.state.status, CalendarStatus.loading);
    await cubit.close();
  });

  test('a failure of the month can be retried', () async {
    final cubit = build();
    await signIn(alice);
    workoutStreams[november]!.addError(const NetworkFailure('offline'));
    await pumpEventQueue();
    expect(cubit.state.status, CalendarStatus.failure);
    expect(cubit.state.failure, const NetworkFailure('offline'));

    workoutStreams.clear();
    cardioStreams.clear();
    programStreams.clear();
    activeStreams.clear();
    cubit.retry();
    expect(cubit.state.status, CalendarStatus.loading);
    await pumpEventQueue();
    await deliver();
    expect(cubit.state.status, CalendarStatus.ready);
    await cubit.close();
  });

  test('a failure, then another month: everything followed again', () async {
    final cubit = build();
    await signIn(alice);
    workoutStreams[november]!.addError(const NetworkFailure('offline'));
    await pumpEventQueue();
    expect(cubit.state.status, CalendarStatus.failure);

    programStreams.clear();
    activeStreams.clear();
    cubit.showMonth(1);
    await pumpEventQueue();
    await deliver(month: 'u1 2026-11-25', activeProgram: active);
    expect(cubit.state.status, CalendarStatus.ready);
    expect(cubit.state.entriesOn(d(2026, 12, 2)), hasLength(1));
    await cubit.close();
  });

  test(
    'after a failure and another month, the active program updates',
    () async {
      final cubit = build();
      await signIn(alice);
      await deliver();
      workoutStreams[november]!.addError(const NetworkFailure('offline'));
      await pumpEventQueue();
      expect(cubit.state.status, CalendarStatus.failure);

      programStreams.clear();
      activeStreams.clear();
      cubit.showMonth(1);
      await pumpEventQueue();
      await deliver(month: 'u1 2026-11-25', sessions: []);
      expect(cubit.state.status, CalendarStatus.ready);
      expect(cubit.state.entriesOn(d(2026, 12, 2)), isEmpty);

      activeStreams['u1']!.add(active);
      await pumpEventQueue();
      expect(cubit.state.entriesOn(d(2026, 12, 2)), [
        PlanEntry(
          upperLower,
          PlannedDay(
            date: d(2026, 12, 2),
            dayIndex: 0,
            status: PlannedStatus.planned,
          ),
        ),
      ]);
      await cubit.close();
    },
  );

  test('without programs it still shows what was done', () async {
    final cubit = build();
    await signIn(alice);
    workoutStreams[november]!.add([legs]);
    cardioStreams[november]!.add([]);
    programStreams['u1']!.addError(const NetworkFailure('offline'));
    activeStreams['u1']!.add(active);
    await pumpEventQueue();
    expect(cubit.state.status, CalendarStatus.ready);
    expect(cubit.state.entries.keys, [today]);
    await cubit.close();
  });

  test('another user: nothing of the previous one', () async {
    final cubit = build();
    await signIn(alice);
    await deliver(activeProgram: active);
    cubit.showMonth(1);

    await signIn(bob);
    expect(cubit.state.month, d(2026, 11, 1));
    expect(cubit.state.status, CalendarStatus.loading);
    expect(cubit.state.entries, isEmpty);
    expect(programStreams['u1']!.hasListener, isFalse);
    await deliver(month: 'u2 2026-10-26', uid: 'u2', done: [], sessions: []);
    expect(cubit.state.status, CalendarStatus.ready);
    expect(cubit.state.entries, isEmpty);
    await cubit.close();
  });
}
