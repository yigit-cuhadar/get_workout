import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/strength/domain/strength.dart';
import 'package:get_workout/features/strength/presentation/exercise_strength_cubit.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/domain/workout_usecases.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

void main() {
  const alice = AuthUser(id: 'u1', isAnonymous: true);
  const bob = AuthUser(id: 'u2', isAnonymous: true);
  final now = DateTime(2026, 11, 12, 12);
  final old = DateTime(2026, 3, 1);
  final recent = DateTime(2026, 11, 1);
  const top = (weightKg: 100.0, reps: 5, durationS: null);
  final heaviest = StatRecord(
    value: 100,
    date: recent,
    workoutId: 'w2',
    set: top,
  );
  final e1rm = StatRecord(
    value: 116.7,
    date: recent,
    workoutId: 'w2',
    set: top,
  );
  final oldPoint = HistoryPoint(
    date: old,
    workoutId: 'w1',
    bestE1rmKg: 90,
    bestSet: (weightKg: 80, reps: 4, durationS: null),
    workoutName: 'Legs',
  );
  final recentPoint = HistoryPoint(
    date: recent,
    workoutId: 'w2',
    bestE1rmKg: 116.7,
    bestSet: top,
    workoutName: 'Legs',
  );
  final squat = ExerciseStats(
    records: {RecordKind.bestE1rm: e1rm, RecordKind.heaviestWeight: heaviest},
    history: [oldPoint, recentPoint],
  );

  late StreamController<AuthUser?> users;
  late StreamController<ExerciseStats?> stats;
  late MockWorkoutRepository repository;

  setUp(() {
    users = StreamController<AuthUser?>.broadcast();
    stats = StreamController<ExerciseStats?>.broadcast();
    repository = MockWorkoutRepository();
    when(() => repository.watchStats(any(), 'squat'))
        .thenAnswer((_) => stats.stream);
    when(() => repository.workoutsWith(any(), any())).thenAnswer(
      (_) async => const Ok((workouts: <Workout>[], complete: false)),
    );
  });

  tearDown(() async {
    await users.close();
    await stats.close();
  });

  ExerciseStrengthCubit build({WeightUnit unit = WeightUnit.kg}) {
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    return ExerciseStrengthCubit(
      exerciseId: 'squat',
      watchAuthUser: WatchAuthUser(auth),
      watchStats: WatchExerciseStats(repository),
      rebuildStats: RebuildExerciseStats(repository),
      unit: unit,
      clock: () => now,
    );
  }

  /// Signs in [alice], then shows [value].
  Future<ExerciseStrengthCubit> opened({
    ExerciseStats? value,
    WeightUnit unit = WeightUnit.kg,
  }) async {
    final cubit = build(unit: unit);
    users.add(alice);
    await pumpEventQueue();
    stats.add(value);
    await pumpEventQueue();
    return cubit;
  }

  List<double> values(ExerciseStrengthState state) => [
    for (final point in state.points) point.value,
  ];

  test('records in order and the last 2 weeks of e1RM', () async {
    final cubit = await opened(value: squat);
    final state = cubit.state;
    expect(state.status, ExerciseStrengthStatus.ready);
    expect(state.trained, isTrue);
    expect(state.records, [
      (kind: RecordKind.bestE1rm, record: e1rm),
      (kind: RecordKind.heaviestWeight, record: heaviest),
    ]);
    expect(state.range, StrengthRange.weeks2);
    expect(state.rangeStart, DateTime(2026, 10, 29));
    expect(values(state), [116.5]);
    expect(state.sessions, [recentPoint]);
    expect(state.loggingType, LoggingType.weightReps);
    verify(() => repository.watchStats('u1', 'squat')).called(1);
    await cubit.close();
  });

  test('a longer range shows everything, without Premium', () async {
    final cubit = await opened(value: squat);
    cubit.selectRange(StrengthRange.all);
    expect(cubit.state.range, StrengthRange.all);
    expect(values(cubit.state), [90, 116.5]);
    expect(cubit.state.sessions, [recentPoint, oldPoint]);
    expect(cubit.state.rangeStart, old);
    await cubit.close();
  });

  test('values in the user unit, changed live', () async {
    final cubit = await opened(value: squat, unit: WeightUnit.lb);
    expect(values(cubit.state).single, 257);
    cubit.setUnit(WeightUnit.kg);
    expect(values(cubit.state), [116.5]);
    await cubit.close();
  });

  test('charted when some workout has an e1RM', () async {
    final cubit = await opened(value: squat);
    expect(cubit.state.charted, isTrue);
    await cubit.close();
  });

  test('a bodyweight or timed exercise has records but no chart', () async {
    final plank = ExerciseStats(
      records: {
        RecordKind.longestDuration: StatRecord(
          value: 90,
          date: recent,
          workoutId: 'w2',
        ),
      },
      history: [
        HistoryPoint(
          date: old,
          workoutId: 'w1',
          bestSet: (weightKg: null, reps: null, durationS: 60),
          workoutName: 'Core',
        ),
        HistoryPoint(
          date: recent,
          workoutId: 'w2',
          bestSet: (weightKg: null, reps: null, durationS: 90),
          workoutName: 'Core',
        ),
      ],
    );
    final cubit = await opened(value: plank);
    expect(cubit.state.trained, isTrue);
    expect(cubit.state.charted, isFalse);
    expect(cubit.state.records.single.kind, RecordKind.longestDuration);
    expect(cubit.state.points, isEmpty);
    // Every session, however old.
    expect(cubit.state.sessions.length, 2);
    expect(cubit.state.loggingType, LoggingType.duration);
    await cubit.close();
  });

  test('an exercise not done yet', () async {
    final cubit = await opened();
    expect(cubit.state.status, ExerciseStrengthStatus.ready);
    expect(cubit.state.trained, isFalse);
    await cubit.close();
  });

  test('a failure shows, and retry follows again', () async {
    final cubit = await opened(value: squat);
    stats.addError(const NetworkFailure());
    await pumpEventQueue();
    expect(cubit.state.status, ExerciseStrengthStatus.failure);

    cubit.retry();
    stats.add(squat);
    await pumpEventQueue();
    expect(cubit.state.status, ExerciseStrengthStatus.ready);
    await cubit.close();
  });

  test('another user starts over at loading and 2 weeks', () async {
    final cubit = await opened(value: squat);
    cubit.selectRange(StrengthRange.all);
    users.add(bob);
    await pumpEventQueue();
    expect(cubit.state, const ExerciseStrengthState());
    verify(() => repository.watchStats('u2', 'squat')).called(1);

    stats.add(squat);
    await pumpEventQueue();
    expect(cubit.state.range, StrengthRange.weeks2);
    await cubit.close();
  });

  test('outdated stats show at once and are rebuilt once', () async {
    final outdated = ExerciseStats(
      records: {
        RecordKind.bestE1rm: StatRecord(
          value: 116.7,
          date: recent,
          workoutId: 'w2',
        ),
      },
      history: [HistoryPoint(date: recent, workoutId: 'w2', bestE1rmKg: 116.7)],
    );
    final cubit = await opened(value: outdated);
    expect(cubit.state.status, ExerciseStrengthStatus.ready);
    verify(() => repository.workoutsWith('u1', 'squat')).called(1);

    stats.add(outdated);
    await pumpEventQueue();
    verifyNever(() => repository.workoutsWith(any(), any()));
    await cubit.close();
  });

  test('up-to-date stats are not rebuilt', () async {
    final cubit = await opened(value: squat);
    verifyNever(() => repository.workoutsWith(any(), any()));
    await cubit.close();
  });

  blocTest<ExerciseStrengthCubit, ExerciseStrengthState>(
    'stays loading until the stats arrive',
    build: build,
    act: (cubit) => cubit.selectRange(StrengthRange.all),
    expect: () => <ExerciseStrengthState>[],
  );
}
