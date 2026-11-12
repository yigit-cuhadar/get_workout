import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/strength/domain/strength.dart';
import 'package:get_workout/features/strength/presentation/exercise_strength_cubit.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/domain/workout_usecases.dart';
import 'package:mocktail/mocktail.dart';

import '../programs/fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

void main() {
  const alice = AuthUser(id: 'u1', isAnonymous: true);
  const bob = AuthUser(id: 'u2', isAnonymous: true);
  final now = DateTime(2026, 11, 12, 12);
  final old = DateTime(2026, 3, 1);
  final recent = DateTime(2026, 11, 1);
  final heaviest = StatRecord(value: 100, date: recent, workoutId: 'w2');
  final e1rm = StatRecord(value: 116.7, date: recent, workoutId: 'w2');
  final squat = ExerciseStats(
    records: {RecordKind.bestE1rm: e1rm, RecordKind.heaviestWeight: heaviest},
    history: [
      HistoryPoint(date: old, workoutId: 'w1', bestE1rmKg: 90),
      HistoryPoint(date: recent, workoutId: 'w2', bestE1rmKg: 116.7),
    ],
  );

  late StreamController<AuthUser?> users;
  late StreamController<ExerciseStats?> stats;
  late FakePremium premium;
  late MockWorkoutRepository repository;

  setUp(() {
    users = StreamController<AuthUser?>.broadcast();
    stats = StreamController<ExerciseStats?>.broadcast();
    premium = FakePremium();
    repository = MockWorkoutRepository();
    when(() => repository.watchStats(any(), 'squat'))
        .thenAnswer((_) => stats.stream);
  });

  tearDown(() async {
    await users.close();
    await stats.close();
    await premium.controller.close();
  });

  ExerciseStrengthCubit build({WeightUnit unit = WeightUnit.kg}) {
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    return ExerciseStrengthCubit(
      exerciseId: 'squat',
      watchAuthUser: WatchAuthUser(auth),
      watchStats: WatchExerciseStats(repository),
      premium: premium,
      unit: unit,
      clock: () => now,
    );
  }

  /// Signs in [user], then shows [value] and [premium] status [hasPremium].
  Future<ExerciseStrengthCubit> opened({
    ExerciseStats? value,
    bool? hasPremium = false,
    WeightUnit unit = WeightUnit.kg,
  }) async {
    final cubit = build(unit: unit);
    users.add(alice);
    await pumpEventQueue();
    premium.controller.add(hasPremium);
    stats.add(value);
    await pumpEventQueue();
    return cubit;
  }

  List<double> values(ExerciseStrengthState state) => [
    for (final point in state.points) point.value,
  ];

  test('records in order and the last 12 weeks of e1RM', () async {
    final cubit = await opened(value: squat);
    final state = cubit.state;
    expect(state.status, ExerciseStrengthStatus.ready);
    expect(state.trained, isTrue);
    expect(state.records, [
      (kind: RecordKind.heaviestWeight, record: heaviest),
      (kind: RecordKind.bestE1rm, record: e1rm),
    ]);
    expect(state.range, StrengthRange.weeks12);
    expect(values(state), [116.7]);
    verify(() => repository.watchStats('u1', 'squat')).called(1);
    await cubit.close();
  });

  test('a free user is told older results exist', () async {
    final cubit = await opened(value: squat);
    expect(cubit.state.olderLocked, isTrue);
    await cubit.close();
  });

  test('nothing is locked while Premium is unknown or owned', () async {
    final unknown = await opened(value: squat, hasPremium: null);
    expect(unknown.state.olderLocked, isFalse);
    await unknown.close();

    final owned = await opened(value: squat, hasPremium: true);
    expect(owned.state.olderLocked, isFalse);
    await owned.close();
  });

  test('a Premium range shows everything to a Premium user', () async {
    final cubit = await opened(value: squat, hasPremium: true);
    cubit.selectRange(StrengthRange.all);
    expect(cubit.state.range, StrengthRange.all);
    expect(values(cubit.state), [90, 116.7]);
    await cubit.close();
  });

  test('a Premium range waits for Premium to arrive', () async {
    final cubit = await opened(value: squat);
    cubit.selectRange(StrengthRange.year1);
    expect(cubit.state.range, StrengthRange.weeks12);
    expect(values(cubit.state), [116.7]);

    // The paywall closed before the status caught up.
    premium.controller.add(true);
    await pumpEventQueue();
    expect(cubit.state.range, StrengthRange.year1);
    expect(values(cubit.state), [90, 116.7]);

    // Premium ending falls back to the free range.
    premium.controller.add(false);
    await pumpEventQueue();
    expect(cubit.state.range, StrengthRange.weeks12);
    await cubit.close();
  });

  test('values in the user unit, changed live', () async {
    final cubit = await opened(value: squat, unit: WeightUnit.lb);
    expect(values(cubit.state).single, closeTo(257.28, 0.01));
    cubit.setUnit(WeightUnit.kg);
    expect(values(cubit.state), [116.7]);
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

  test('another user starts over at loading and the free range', () async {
    final cubit = await opened(value: squat, hasPremium: true);
    cubit.selectRange(StrengthRange.all);
    users.add(bob);
    await pumpEventQueue();
    expect(cubit.state, const ExerciseStrengthState());
    verify(() => repository.watchStats('u2', 'squat')).called(1);

    stats.add(squat);
    await pumpEventQueue();
    expect(cubit.state.range, StrengthRange.weeks12);
    await cubit.close();
  });

  blocTest<ExerciseStrengthCubit, ExerciseStrengthState>(
    'stays loading until the stats arrive',
    build: build,
    act: (cubit) async {
      premium.controller.add(true);
      cubit.selectRange(StrengthRange.all);
    },
    expect: () => <ExerciseStrengthState>[],
  );
}
