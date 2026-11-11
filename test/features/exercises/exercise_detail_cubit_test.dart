import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_detail_cubit.dart';

import 'fixtures.dart';

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
final _all = [_bench, _machinePress, _dumbbellBench];

void main() {
  late MockCatalogueCubit catalogue;
  late MockEquipmentCubit equipment;
  late StreamController<ExerciseCatalogueState> catalogueChanges;
  late StreamController<EquipmentState> equipmentChanges;

  setUp(() {
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

  ExerciseDetailCubit build(String id) =>
      ExerciseDetailCubit(id, catalogue: catalogue, equipment: equipment);

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
}
