import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/history_usecases.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/domain/workout_usecases.dart';
import 'package:get_workout/features/workout/presentation/workout_edit_cubit.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

void main() {
  const alice = AuthUser(id: 'u1', isAnonymous: true);
  const bob = AuthUser(id: 'u2', isAnonymous: true);
  final now = DateTime(2026, 11, 11, 18, 40);
  final start = DateTime(2026, 11, 10, 18);
  final legs = workout(
    'w1',
    [
      exercise('squat', [lift(100, 5)]),
    ],
    startedAt: start,
    finishedAt: start.add(const Duration(minutes: 50)),
  );

  late StreamController<AuthUser?> users;
  late StreamController<StoredWorkout?> stored;
  late MockWorkoutRepository repository;
  late List<({String id, bool deleted, Set<String> stale})> changes;

  setUpAll(() {
    registerFallbackValue(legs);
    registerFallbackValue(<String, ExerciseStats?>{});
  });

  setUp(() {
    users = StreamController<AuthUser?>.broadcast();
    stored = StreamController<StoredWorkout?>.broadcast();
    repository = MockWorkoutRepository();
    changes = [];
    when(() => repository.watchWorkout('u1', 'w1'))
        .thenAnswer((_) => stored.stream);
    when(() => repository.newWorkoutId('u1')).thenReturn('w9');
    when(() => repository.workoutsDoing('u1', any())).thenAnswer(
      (call) async => Ok((
        workouts: {
          for (final id in call.positionalArguments[1] as List<String>)
            id: (workouts: [legs], complete: true),
        },
        current: true,
      )),
    );
    when(() => repository.updateWorkout(any(), any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  tearDown(() async {
    await users.close();
    await stored.close();
  });

  WorkoutEditCubit build({String? id = 'w1'}) {
    final auth = MockAuthRepository();
    when(() => auth.currentUser).thenReturn(alice);
    when(auth.watchUser).thenAnswer((_) => users.stream);
    final catalogue = MockCatalogueCubit();
    when(() => catalogue.state).thenReturn(CatalogueReady([move('row')]));
    return WorkoutEditCubit(
      id: id,
      name: 'Workout',
      getCurrentUser: GetCurrentUser(auth),
      watchAuthUser: WatchAuthUser(auth),
      watchWorkout: WatchStoredWorkout(repository),
      newWorkoutId: NewWorkoutId(repository),
      saveChange: SaveWorkoutChange(repository),
      changed: (_, id, {required deleted, required staleStats}) =>
          changes.add((id: id, deleted: deleted, stale: staleStats)),
      catalogue: catalogue,
      clock: () => now,
    );
  }

  Future<WorkoutEditCubit> editing() async {
    final cubit = build();
    stored.add((workout: legs, pending: false));
    await pumpEventQueue();
    return cubit;
  }

  Workout saved() =>
      verify(() => repository.updateWorkout('u1', captureAny(), any()))
              .captured
              .single
          as Workout;

  group('opening', () {
    test('a workout awaiting the server is edited once confirmed', () async {
      final cubit = build();
      expect(cubit.state.status, WorkoutEditStatus.loading);
      stored.add((workout: legs, pending: true));
      await pumpEventQueue();
      expect(cubit.state.status, WorkoutEditStatus.syncing);
      cubit.setName('Too early');
      expect(cubit.state.workout, isNull);

      stored.add((workout: legs, pending: false));
      await pumpEventQueue();
      expect(cubit.state.status, WorkoutEditStatus.editing);
      expect(cubit.state.workout, legs);
      expect(cubit.hasChanges, isFalse);
      // Later snapshots no longer replace the edits.
      cubit.setName('Legs day');
      stored.add((workout: legs, pending: false));
      await pumpEventQueue();
      expect(cubit.state.workout!.name, 'Legs day');
      expect(cubit.hasChanges, isTrue);
      await cubit.close();
    });

    test('a workout gone is missing', () async {
      final cubit = build();
      stored.add(null);
      await pumpEventQueue();
      expect(cubit.state.status, WorkoutEditStatus.missing);
      await cubit.close();
    });

    test('a past workout starts the hour before last, an hour long', () async {
      final cubit = build(id: null);
      expect(cubit.isNew, isTrue);
      expect(cubit.state.status, WorkoutEditStatus.editing);
      final workout = cubit.state.workout!;
      expect(workout.id, 'w9');
      expect(workout.name, 'Workout');
      expect(workout.startedAt, DateTime(2026, 11, 11, 17));
      expect(workout.finishedAt, DateTime(2026, 11, 11, 18));
      expect(workout.programId, isNull);
      expect(workout.exercises, isEmpty);
      await cubit.close();
    });

    test('another user closes it', () async {
      final cubit = await editing();
      users.add(bob);
      await pumpEventQueue();
      expect(cubit.state.status, WorkoutEditStatus.closed);
      await cubit.close();
    });
  });

  group('editing', () {
    test('a new start keeps the duration; durations stay in range', () async {
      final cubit = await editing();
      final later = start.add(const Duration(hours: 2));
      cubit.setStart(later);
      expect(cubit.state.workout!.startedAt, later);
      expect(
        cubit.state.workout!.finishedAt,
        later.add(const Duration(minutes: 50)),
      );
      cubit.setTotalDuration(const Duration(hours: 30));
      expect(
        cubit.state.workout!.finishedAt,
        later.add(WorkoutEditCubit.maxDuration),
      );
      cubit.setTotalDuration(const Duration(minutes: -5));
      expect(cubit.state.workout!.finishedAt, later);
      await cubit.close();
    });

    test('a new set takes the values of the set before it', () async {
      final cubit = await editing();
      cubit.addSet(0);
      cubit.toggleDone((exercise: 0, set: 1));
      expect(cubit.state.workout!.exercises.single.sets, [
        lift(100, 5),
        lift(100, 5),
      ]);
      // No last time here.
      expect(cubit.state.lastTime((exercise: 0, set: 0)), isNull);
      await cubit.close();
    });

    test('a set that cannot be ticked is marked', () async {
      final cubit = build(id: null);
      cubit.addExercises([move('row')], 'en');
      cubit.toggleDone((exercise: 0, set: 0));
      expect(cubit.state.invalidSet, (exercise: 0, set: 0));
      cubit.setWeight((exercise: 0, set: 0), '70', WeightUnit.kg);
      expect(cubit.state.invalidSet, isNull);
      await cubit.close();
    });
  });

  group('saving', () {
    test('stores the edit with its rebuilt stats', () async {
      final cubit = await editing();
      cubit.setName('  Legs day ');
      cubit.addExercises([move('row')], 'en');
      cubit.setWeight((exercise: 1, set: 0), '70', WeightUnit.kg);
      cubit.setReps((exercise: 1, set: 0), '8');
      cubit.toggleDone((exercise: 1, set: 0));
      await cubit.save();

      final workout = saved();
      expect(workout.name, 'Legs day');
      expect(workout.exerciseIds, ['squat', 'row']);
      verify(() => repository.workoutsDoing('u1', ['squat', 'row'])).called(1);
      expect(changes.single.id, 'w1');
      expect(changes.single.deleted, isFalse);
      expect(changes.single.stale, isEmpty);
      expect(cubit.state.status, WorkoutEditStatus.saved);
      expect(cubit.hasChanges, isFalse);
      await cubit.close();
    });

    test('a past workout is added with its stats', () async {
      final cubit = build(id: null);
      cubit.addExercises([move('row')], 'en');
      cubit.setWeight((exercise: 0, set: 0), '70', WeightUnit.kg);
      cubit.setReps((exercise: 0, set: 0), '8');
      cubit.toggleDone((exercise: 0, set: 0));
      await cubit.save();
      expect(saved().id, 'w9');
      expect(changes.single.id, 'w9');
      await cubit.close();
    });

    test('stats read from the cache are reported stale', () async {
      when(() => repository.workoutsDoing('u1', ['squat'])).thenAnswer(
        (_) async => Ok((
          workouts: {
            'squat': (workouts: [legs], complete: true),
          },
          current: false,
        )),
      );
      final cubit = await editing();
      await cubit.save();
      expect(changes.single.stale, {'squat'});
      await cubit.close();
    });

    test('nothing ticked or a start in the future is refused', () async {
      final cubit = await editing();
      cubit.toggleDone((exercise: 0, set: 0));
      await cubit.save();
      expect(cubit.state.issue, WorkoutEditIssue.noDoneSet);
      cubit.problemShown();
      cubit.toggleDone((exercise: 0, set: 0));
      cubit.setStart(now.add(const Duration(minutes: 5)));
      await cubit.save();
      expect(cubit.state.issue, WorkoutEditIssue.startInFuture);
      verifyNever(() => repository.updateWorkout(any(), any(), any()));
      expect(cubit.state.status, WorkoutEditStatus.editing);
      await cubit.close();
    });

    test('an invalid workout is refused and stays open', () async {
      final cubit = await editing();
      cubit.setName('   ');
      await cubit.save();
      expect(cubit.state.issue, WorkoutEditIssue.invalid);
      expect(cubit.state.status, WorkoutEditStatus.editing);
      verifyNever(() => repository.updateWorkout(any(), any(), any()));
      await cubit.close();
    });

    test('a failure keeps the edits', () async {
      when(() => repository.workoutsDoing(any(), any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      final cubit = await editing();
      cubit.setName('Legs day');
      await cubit.save();
      expect(cubit.state.status, WorkoutEditStatus.editing);
      expect(cubit.state.failure, isA<NetworkFailure>());
      expect(cubit.state.workout!.name, 'Legs day');
      expect(changes, isEmpty);
      cubit.problemShown();
      expect(cubit.state.failure, isNull);
      await cubit.close();
    });
  });
}
