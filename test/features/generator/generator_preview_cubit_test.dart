import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/generator/domain/generator_answers.dart';
import 'package:get_workout/features/generator/domain/generator_usecases.dart';
import 'package:get_workout/features/generator/domain/program_generator.dart';
import 'package:get_workout/features/generator/presentation/generator_preview_cubit.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

void main() {
  final library = contentLibrary();
  final given = answers(days: 3, split: TrainingSplit.upperLower);

  late MockProgramRepository repository;
  late MockCatalogueCubit catalogue;
  late StreamController<ExerciseCatalogueState> libraries;

  setUpAll(() => registerFallbackValue(const Program(name: '', days: [])));

  setUp(() {
    repository = MockProgramRepository();
    when(() => repository.createProgram('u1', any()))
        .thenAnswer((_) async => const Ok('p9'));
    catalogue = MockCatalogueCubit();
    libraries = StreamController<ExerciseCatalogueState>.broadcast();
    when(() => catalogue.stream).thenAnswer((_) => libraries.stream);
    when(() => catalogue.state).thenReturn(const CatalogueLoading());
    when(() => catalogue.retry()).thenAnswer((_) async {});
  });

  tearDown(() => libraries.close());

  GeneratorPreviewCubit build([
    GeneratorAnswers? answers,
    AuthUser? user = const AuthUser(id: 'u1', isAnonymous: true),
  ]) {
    final auth = MockAuthRepository();
    when(() => auth.currentUser).thenReturn(user);
    return GeneratorPreviewCubit(
      answers ?? given,
      catalogue: catalogue,
      generateProgram: const GenerateProgram(),
      saveProgram: SaveProgram(repository),
      getCurrentUser: GetCurrentUser(auth),
    );
  }

  void libraryArrives() {
    final ready = CatalogueReady(library);
    when(() => catalogue.state).thenReturn(ready);
    libraries.add(ready);
  }

  GeneratedProgram expected(int seed) =>
      generateProgram(given, library, seed: seed).valueOrNull!;

  test('waits for the library, then generates', () async {
    final cubit = build();
    expect(cubit.state, const GeneratorPreviewState());
    libraryArrives();
    await pumpEventQueue();
    expect(
      cubit.state,
      GeneratorPreviewState(status: PreviewStatus.ready, program: expected(0)),
    );
    await cubit.close();
  });

  test('generates at once from a library already loaded', () async {
    when(() => catalogue.state).thenReturn(CatalogueReady(library));
    final cubit = build();
    await pumpEventQueue();
    expect(cubit.state.program, expected(0));
    await cubit.close();
  });

  test('keeps the program when the library changes', () async {
    when(() => catalogue.state).thenReturn(CatalogueReady(library));
    final cubit = build();
    await pumpEventQueue();
    libraries.add(CatalogueReady(library.skip(1).toList()));
    await pumpEventQueue();
    expect(cubit.state.program, expected(0));
    await cubit.close();
  });

  test('regenerates with the next seed', () async {
    when(() => catalogue.state).thenReturn(CatalogueReady(library));
    final cubit = build();
    await pumpEventQueue();
    await cubit.regenerate();
    expect(cubit.state.seed, 1);
    expect(cubit.state.program, expected(1));
    await cubit.regenerate();
    expect(cubit.state.program, expected(2));
    await cubit.close();
  });

  test('says why answers give no program', () async {
    when(() => catalogue.state).thenReturn(CatalogueReady(library));
    final cubit = build(answers(days: 2, split: TrainingSplit.pushPullLegs));
    await pumpEventQueue();
    expect(
      cubit.state,
      const GeneratorPreviewState(
        status: PreviewStatus.impossible,
        issue: GenerationIssue.splitNeedsMoreDays,
      ),
    );
    await cubit.regenerate();
    expect(cubit.state.status, PreviewStatus.impossible);
    await cubit.close();
  });

  test('a library that fails is retried', () async {
    when(() => catalogue.state)
        .thenReturn(const CatalogueFailed(NetworkFailure()));
    final cubit = build();
    expect(cubit.state.status, PreviewStatus.libraryFailed);
    await cubit.retry();
    verify(() => catalogue.retry()).called(1);
    libraries.add(const CatalogueLoading());
    await pumpEventQueue();
    expect(cubit.state.status, PreviewStatus.loading);
    libraryArrives();
    await pumpEventQueue();
    expect(cubit.state.status, PreviewStatus.ready);
    await cubit.close();
  });

  test('saves the program as a generated one of the user', () async {
    when(() => catalogue.state).thenReturn(CatalogueReady(library));
    final cubit = build();
    await pumpEventQueue();
    await cubit.regenerate();
    await cubit.save(
      name: '  Upper/lower, 3 days ',
      dayName: (day) => '${day.kind.name} ${day.variant}',
    );
    expect(cubit.state.saveStatus, SaveStatus.saved);
    expect(cubit.state.savedId, 'p9');
    final saved =
        verify(() => repository.createProgram('u1', captureAny()))
                .captured
                .single
            as Program;
    expect(
      saved,
      expected(1).toProgram(
        name: 'Upper/lower, 3 days',
        dayName: (day) => '${day.kind.name} ${day.variant}',
      ),
    );
    expect(saved.origin, ProgramOrigin.generated);
    expect(saved.days.map((d) => d.name), ['upper 0', 'lower null', 'upper 1']);
    // Saved once only.
    await cubit.save(name: 'Again', dayName: (_) => '');
    verifyNever(() => repository.createProgram(any(), any()));
    await cubit.close();
  });

  test('reports a failed save, then lets the user try again', () async {
    when(() => repository.createProgram('u1', any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => catalogue.state).thenReturn(CatalogueReady(library));
    final cubit = build();
    await pumpEventQueue();
    await cubit.save(name: 'Mine', dayName: (_) => '');
    expect(cubit.state.saveStatus, SaveStatus.failed);
    expect(cubit.state.saveFailure, isA<NetworkFailure>());
    cubit.saveFailureShown();
    expect(cubit.state.saveStatus, SaveStatus.idle);
    expect(cubit.state.saveFailure, isNull);
    expect(cubit.state.program, expected(0));
    await cubit.close();
  });

  test('refuses to save exercises gone from the library', () async {
    when(() => catalogue.state).thenReturn(CatalogueReady(library));
    final cubit = build();
    await pumpEventQueue();
    final used = cubit.state.program!.days.first.items.first.exerciseId;
    when(() => catalogue.state).thenReturn(
      CatalogueReady([
        for (final e in library)
          if (e.id != used) e,
      ]),
    );
    await cubit.save(name: 'Mine', dayName: (_) => '');
    expect(cubit.state.saveStatus, SaveStatus.failed);
    expect(cubit.state.saveFailure, isA<ValidationFailure>());
    verifyNever(() => repository.createProgram(any(), any()));
    await cubit.close();
  });

  test('says why it cannot save while nobody is signed in', () async {
    when(() => catalogue.state).thenReturn(CatalogueReady(library));
    final cubit = build(null, null);
    await pumpEventQueue();
    await cubit.save(name: 'Mine', dayName: (_) => '');
    expect(cubit.state.saveStatus, SaveStatus.failed);
    expect(cubit.state.saveFailure, isA<AuthFailure>());
    verifyNever(() => repository.createProgram(any(), any()));
    await cubit.close();
  });

  test('says why it cannot save while the library reloads', () async {
    when(() => catalogue.state).thenReturn(CatalogueReady(library));
    final cubit = build();
    await pumpEventQueue();
    when(() => catalogue.state).thenReturn(const CatalogueLoading());
    await cubit.save(name: 'Mine', dayName: (_) => '');
    expect(cubit.state.saveStatus, SaveStatus.failed);
    expect(cubit.state.saveFailure, isA<NotFoundFailure>());
    verifyNever(() => repository.createProgram(any(), any()));
    await cubit.close();
  });
}
