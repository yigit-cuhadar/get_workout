import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_detail_cubit.dart';

import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockCustomExerciseRepository extends Mock
    implements CustomExerciseRepository {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class MockEquipmentCubit extends MockCubit<EquipmentState>
    implements EquipmentCubit {}

final _bench = exercise(
  'bench',
  popularity: 1,
  equipment: [Equipment.barbell, Equipment.bench],
  family: 'bench_press',
  familyRank: 2,
);
final _dumbbellBench = exercise(
  'dumbbell_bench',
  popularity: 3,
  equipment: [Equipment.dumbbell, Equipment.bench],
  family: 'bench_press',
  familyRank: 1,
);
final _machinePress = exercise(
  'machine_press',
  popularity: 2,
  equipment: [Equipment.machine],
  family: 'machine_press',
);
final _custom = Exercise.custom(
  id: 'custom_press',
  name: 'Band Press',
  loggingType: LoggingType.reps,
  mainMuscles: const [Muscle.pec],
);
final _all = [_bench, _machinePress, _dumbbellBench];

void main() {
  late MockCatalogueCubit catalogue;
  late MockEquipmentCubit equipment;
  late StreamController<ExerciseCatalogueState> catalogueChanges;
  late StreamController<EquipmentState> equipmentChanges;
  late MockAuthRepository auth;
  late MockCustomExerciseRepository customRepository;

  setUp(() {
    auth = MockAuthRepository();
    customRepository = MockCustomExerciseRepository();
    when(() => auth.currentUser)
        .thenReturn(const AuthUser(id: 'u1', isAnonymous: true));
    catalogue = MockCatalogueCubit();
    equipment = MockEquipmentCubit();
    catalogueChanges = StreamController.broadcast();
    equipmentChanges = StreamController.broadcast();
    whenListen(
      catalogue,
      catalogueChanges.stream,
      initialState: CatalogueReady(_all),
    );
    whenListen(
      equipment,
      equipmentChanges.stream,
      initialState: const EquipmentState(null),
    );
  });

  tearDown(() async {
    await catalogueChanges.close();
    await equipmentChanges.close();
  });

  ExerciseDetailCubit build(String id) => ExerciseDetailCubit(
    id,
    catalogue: catalogue,
    equipment: equipment,
    getCurrentUser: GetCurrentUser(auth),
    deleteCustomExercise: DeleteCustomExercise(customRepository),
  );

  test('shows the exercise with its alternatives and variations', () {
    final state = build('bench').state as DetailReady;
    expect(state.exercise, _bench);
    // Unknown equipment: nothing is doable, so popularity decides.
    expect(ids(state.alternatives), ['machine_press', 'dumbbell_bench']);
    expect(ids(state.variations), ['dumbbell_bench']);
  });

  blocTest<ExerciseDetailCubit, ExerciseDetailState>(
    "alternatives follow the user's equipment",
    build: () => build('bench'),
    act: (_) => equipmentChanges.add(
      const EquipmentState({Equipment.dumbbell, Equipment.bench}),
    ),
    expect: () => [
      DetailReady(
        _bench,
        alternatives: [_dumbbellBench, _machinePress],
        variations: [_dumbbellBench],
      ),
    ],
  );

  test('an unknown id is not found', () {
    expect(build('retired').state, const DetailNotFound());
  });

  blocTest<ExerciseDetailCubit, ExerciseDetailState>(
    'an exercise retired while open turns into not found',
    build: () => build('bench'),
    act: (_) => catalogueChanges.add(CatalogueReady([_machinePress])),
    expect: () => [const DetailNotFound()],
  );

  test('follows the catalogue while it loads or fails', () {
    whenListen(
      catalogue,
      catalogueChanges.stream,
      initialState: const CatalogueLoading(),
    );
    expect(build('bench').state, const DetailLoading());

    whenListen(
      catalogue,
      catalogueChanges.stream,
      initialState: const CatalogueFailed(NetworkFailure()),
    );
    expect(build('bench').state, const DetailFailed());
  });

  blocTest<ExerciseDetailCubit, ExerciseDetailState>(
    'waits for the catalogue, then shows the exercise, never not found',
    setUp: () => whenListen(
      catalogue,
      catalogueChanges.stream,
      initialState: const CatalogueLoading(),
    ),
    build: () => build('bench'),
    act: (_) => catalogueChanges.add(CatalogueReady(_all)),
    expect: () => [
      DetailReady(
        _bench,
        alternatives: [_machinePress, _dumbbellBench],
        variations: [_dumbbellBench],
      ),
    ],
    verify: (cubit) => expect(cubit.state, isA<DetailReady>()),
  );

  group('a custom exercise', () {
    setUp(
      () => whenListen(
        catalogue,
        catalogueChanges.stream,
        initialState: CatalogueReady([_custom, ..._all]),
      ),
    );

    test('has no alternatives or variations and is no one\'s', () {
      expect(build('custom_press').state, DetailReady(_custom));
      final bench = build('bench').state as DetailReady;
      expect(ids(bench.alternatives), isNot(contains('custom_press')));
    });

    blocTest<ExerciseDetailCubit, ExerciseDetailState>(
      'is deleted, without showing it missing while the page closes',
      setUp: () =>
          when(
            () => customRepository.deleteCustomExercise('u1', 'custom_press'),
          ).thenAnswer((_) async {
            // Firestore's cache drops it before the write returns.
            catalogueChanges.add(CatalogueReady(_all));
            await pumpEventQueue();
            return const Ok(null);
          }),
      build: () => build('custom_press'),
      act: (cubit) => cubit.delete(),
      expect: () => [
        DetailReady(_custom, deleting: true),
        const DetailDeleted(),
      ],
    );

    blocTest<ExerciseDetailCubit, ExerciseDetailState>(
      'stays when the delete fails, with the failure',
      setUp: () => when(
        () => customRepository.deleteCustomExercise('u1', 'custom_press'),
      ).thenAnswer((_) async => const Err(PermissionFailure())),
      build: () => build('custom_press'),
      act: (cubit) => cubit.delete(),
      expect: () => [
        DetailReady(_custom, deleting: true),
        DetailReady(_custom, deleteFailure: const PermissionFailure()),
      ],
    );
  });

  blocTest<ExerciseDetailCubit, ExerciseDetailState>(
    'a catalogue exercise cannot be deleted',
    build: () => build('bench'),
    act: (cubit) => cubit.delete(),
    expect: () => <ExerciseDetailState>[],
    verify: (_) =>
        verifyNever(() => customRepository.deleteCustomExercise(any(), any())),
  );
}
