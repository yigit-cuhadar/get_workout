import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/history_usecases.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/presentation/workout_detail_cubit.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

void main() {
  const alice = AuthUser(id: 'u1', isAnonymous: true);
  const bob = AuthUser(id: 'u2', isAnonymous: true);
  final legs = workout('w1', [
    exercise('squat', [lift(100, 5)]),
  ], finishedAt: DateTime(2026, 11, 11, 19));

  late StreamController<AuthUser?> users;
  late StreamController<StoredWorkout?> stored;
  late MockWorkoutRepository repository;
  late List<({String uid, String id, bool deleted, Set<String> stale})> changes;

  setUpAll(() {
    registerFallbackValue(<String, ExerciseStats?>{});
  });

  setUp(() {
    users = StreamController<AuthUser?>.broadcast();
    stored = StreamController<StoredWorkout?>.broadcast();
    repository = MockWorkoutRepository();
    changes = [];
    when(() => repository.watchWorkout('u1', 'w1'))
        .thenAnswer((_) => stored.stream);
    when(() => repository.workoutsDoing('u1', ['squat'])).thenAnswer(
      (_) async => Ok((
        workouts: {
          'squat': (workouts: [legs], complete: true),
        },
        current: false,
      )),
    );
    when(() => repository.deleteWorkout(any(), any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  tearDown(() async {
    await users.close();
    await stored.close();
  });

  WorkoutDetailCubit build({AuthUser? user = alice}) {
    final auth = MockAuthRepository();
    when(() => auth.currentUser).thenReturn(user);
    when(auth.watchUser).thenAnswer((_) => users.stream);
    return WorkoutDetailCubit(
      id: 'w1',
      getCurrentUser: GetCurrentUser(auth),
      watchAuthUser: WatchAuthUser(auth),
      watchWorkout: WatchStoredWorkout(repository),
      saveChange: SaveWorkoutChange(repository),
      changed: (uid, id, {required deleted, required staleStats}) =>
          changes.add((uid: uid, id: id, deleted: deleted, stale: staleStats)),
    );
  }

  Future<void> show(StoredWorkout? value) async {
    stored.add(value);
    await pumpEventQueue();
  }

  test('shows the workout as stored', () async {
    final cubit = build();
    expect(cubit.state.status, WorkoutDetailStatus.loading);
    await show((workout: legs, pending: false));
    expect(cubit.state.status, WorkoutDetailStatus.ready);
    expect(cubit.state.workout, legs);
    expect(cubit.state.canChange, isTrue);
    await cubit.close();
  });

  test('one awaiting the server cannot be changed', () async {
    final cubit = build();
    await show((workout: legs, pending: true));
    expect(cubit.state.canChange, isFalse);
    await cubit.delete();
    verifyNever(() => repository.deleteWorkout(any(), any(), any()));
    // Confirmed, it can.
    await show((workout: legs, pending: false));
    expect(cubit.state.canChange, isTrue);
    await cubit.close();
  });

  test('deleting rebuilds the stats and tells what to repair', () async {
    final cubit = build();
    await show((workout: legs, pending: false));
    await cubit.delete();
    final stats =
        verify(() => repository.deleteWorkout('u1', 'w1', captureAny()))
                .captured
                .single
            as Map<String, ExerciseStats?>;
    expect(stats, {'squat': null});
    final change = changes.single;
    expect((change.uid, change.id, change.deleted), ('u1', 'w1', true));
    expect(change.stale, {'squat'});
    expect(cubit.state.status, WorkoutDetailStatus.deleted);
    // The snapshot without it does not turn the page into "missing".
    await show(null);
    expect(cubit.state.status, WorkoutDetailStatus.deleted);
    await cubit.close();
  });

  test('a delete that fails is reported and the workout stays', () async {
    when(() => repository.workoutsDoing(any(), any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    final cubit = build();
    await show((workout: legs, pending: false));
    await cubit.delete();
    expect(cubit.state.status, WorkoutDetailStatus.ready);
    expect(cubit.state.failure, isA<NetworkFailure>());
    expect(changes, isEmpty);
    cubit.failureShown();
    expect(cubit.state.failure, isNull);
    await cubit.close();
  });

  test('a workout gone is missing', () async {
    final cubit = build();
    await show(null);
    expect(cubit.state.status, WorkoutDetailStatus.missing);
    await cubit.close();
  });

  test('a failure is shown and retried', () async {
    final cubit = build();
    stored.addError(const NetworkFailure());
    await pumpEventQueue();
    expect(cubit.state.status, WorkoutDetailStatus.failure);
    cubit.retry();
    await show((workout: legs, pending: false));
    expect(cubit.state.status, WorkoutDetailStatus.ready);
    await cubit.close();
  });

  test('another user closes it', () async {
    final cubit = build();
    await show((workout: legs, pending: false));
    users.add(bob);
    await pumpEventQueue();
    expect(cubit.state.status, WorkoutDetailStatus.closed);
    expect(cubit.state.workout, isNull);
    await cubit.close();
  });
}
