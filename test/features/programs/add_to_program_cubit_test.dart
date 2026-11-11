import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/presentation/add_to_program_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

class MockProgramListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

void main() {
  final mine = Exercise.custom(
    id: '${Exercise.customIdPrefix}1',
    name: 'My Row',
    loggingType: LoggingType.weightReps,
    mainMuscles: const [Muscle.lat],
  );
  final stored = Program(
    id: 'p1',
    name: 'Mine',
    days: [
      ProgramDay(items: [item('a'), item(mine.id)]),
    ],
  );

  late MockProgramRepository repository;
  late MockProgramListCubit list;
  late MockCatalogueCubit catalogue;
  late StreamController<ExerciseCatalogueState> catalogueStates;
  late StreamController<ProgramListState> lists;

  setUpAll(() => registerFallbackValue(stored));

  setUp(() {
    repository = MockProgramRepository();
    when(() => repository.updateProgram('u1', any()))
        .thenAnswer((_) async => const Ok(null));
    list = MockProgramListCubit();
    lists = StreamController<ProgramListState>.broadcast();
    when(() => list.state).thenReturn(const ProgramListState());
    when(() => list.stream).thenAnswer((_) => lists.stream);
    catalogue = MockCatalogueCubit();
    catalogueStates = StreamController<ExerciseCatalogueState>.broadcast();
    when(() => catalogue.stream).thenAnswer((_) => catalogueStates.stream);
  });

  tearDown(() async {
    await lists.close();
    await catalogueStates.close();
  });

  AddToProgramCubit build() {
    final auth = MockAuthRepository();
    when(() => auth.currentUser)
        .thenReturn(const AuthUser(id: 'u1', isAnonymous: true));
    return AddToProgramCubit(
      list: list,
      addExercise: AddExerciseToProgram(SaveProgram(repository)),
      catalogue: catalogue,
      getCurrentUser: GetCurrentUser(auth),
    );
  }

  test('follows the programs once they are known', () async {
    final cubit = build();
    expect(cubit.state, const AddToProgramState());
    lists.add(
      ProgramListState(status: ProgramListStatus.ready, programs: [stored]),
    );
    await pumpEventQueue();
    expect(cubit.state, AddToProgramState(ready: true, programs: [stored]));
    await cubit.close();
  });

  test('waits for custom exercises before adding', () async {
    when(
      () => catalogue.state,
    ).thenReturn(CatalogueReady([move('a'), move('b')], customLoaded: false));
    final cubit = build();
    final added = cubit.add(stored, 0, move('b'));
    await pumpEventQueue();
    verifyNever(() => repository.updateProgram(any(), any()));
    final ready = CatalogueReady([move('a'), move('b'), mine]);
    when(() => catalogue.state).thenReturn(ready);
    catalogueStates.add(ready);
    expect(await added, isTrue);
    final saved =
        verify(() => repository.updateProgram('u1', captureAny()))
                .captured
                .single
            as Program;
    expect(saved.days.single.items.map((i) => i.exerciseId), [
      'a',
      mine.id,
      'b',
    ]);
    await cubit.close();
  });
}
