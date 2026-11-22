import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/generator/domain/generated_program.dart';
import 'package:get_workout/features/generator/domain/generator_repository.dart';
import 'package:get_workout/features/generator/domain/generator_usecases.dart';
import 'package:get_workout/features/generator/presentation/generator_preview_cubit.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:mocktail/mocktail.dart';

import '../../fake_analytics.dart';
import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

void main() {
  final library = [
    lift('squat', [Muscle.quads]),
    lift('bench', [Muscle.pec]),
    lift('row', [Muscle.lat]),
    lift('raise', [Muscle.calf]),
    lift('curl', [Muscle.biceps]),
  ];
  final given = answers(days: 2);
  final first = generated(
    [
      ['squat', 'bench'],
      ['row', 'bench'],
    ],
    uncovered: {Muscle.calf, Muscle.biceps},
  );

  late FakeGeneratorRepository generator;
  late MockProgramRepository programs;
  late MockCatalogueCubit catalogue;
  late StreamController<ExerciseCatalogueState> libraries;
  late RecordingTelemetry telemetry;

  setUpAll(() => registerFallbackValue(const Program(name: '', days: [])));

  setUp(() {
    generator = FakeGeneratorRepository()..answer = (_) => Ok(first);
    programs = MockProgramRepository();
    when(() => programs.createProgram('u1', any()))
        .thenAnswer((_) async => const Ok('p9'));
    catalogue = MockCatalogueCubit();
    libraries = StreamController<ExerciseCatalogueState>.broadcast();
    when(() => catalogue.stream).thenAnswer((_) => libraries.stream);
    when(() => catalogue.state).thenReturn(CatalogueReady(library));
    telemetry = RecordingTelemetry();
  });

  tearDown(() => libraries.close());

  GeneratorPreviewCubit build({
    AuthUser? user = const AuthUser(id: 'u1', isAnonymous: true),
  }) {
    final auth = MockAuthRepository();
    when(() => auth.currentUser).thenReturn(user);
    return GeneratorPreviewCubit(
      given,
      language: 'tr',
      analytics: fakeAnalytics(telemetry),
      catalogue: catalogue,
      generateProgram: GenerateProgram(generator),
      saveProgram: SaveProgram(programs),
      getCurrentUser: GetCurrentUser(auth),
    );
  }

  Future<GeneratorPreviewCubit> ready() async {
    final cubit = build();
    addTearDown(cubit.close);
    await pumpEventQueue();
    return cubit;
  }

  test('builds, then shows the program', () async {
    final pending = Completer<Result<GeneratedProgram>>();
    generator.answer = null;
    final repository = _Deferred(pending.future);
    final auth = MockAuthRepository();
    when(() => auth.currentUser).thenReturn(null);
    final cubit = GeneratorPreviewCubit(
      given,
      language: 'tr',
      analytics: fakeAnalytics(telemetry),
      catalogue: catalogue,
      generateProgram: GenerateProgram(repository),
      saveProgram: SaveProgram(programs),
      getCurrentUser: GetCurrentUser(auth),
    );
    addTearDown(cubit.close);
    expect(cubit.state, const GeneratorPreviewState());

    pending.complete(Ok(first));
    await pumpEventQueue();
    expect(
      cubit.state,
      GeneratorPreviewState(
        status: PreviewStatus.ready,
        program: first,
        uncovered: const {Muscle.calf, Muscle.biceps},
      ),
    );
  });

  test(
    'asks with the answers, seed 0, no kept items and the language',
    () async {
      await ready();
      final request = generator.requests.single;
      expect(request.answers, given);
      expect(request.seed, 0);
      expect(request.kept, isEmpty);
      expect(request.language, 'tr');
    },
  );

  test('logs every program the server returns', () async {
    final cubit = await ready();
    await cubit.regenerate();
    expect(telemetry.names, ['program_generate', 'program_generate']);
  });

  group('a failure', () {
    for (final (failure, status) in [
      (const NetworkFailure(), PreviewStatus.offline),
      (
        const GenerationRefused(GenerationRefusal.noTemplate, ''),
        PreviewStatus.noProgram,
      ),
      (
        const GenerationRefused(GenerationRefusal.noExercises, ''),
        PreviewStatus.noProgram,
      ),
      (
        const GenerationRefused(GenerationRefusal.noRules, ''),
        PreviewStatus.unavailable,
      ),
      (
        const GenerationRefused(GenerationRefusal.invalidInput, ''),
        PreviewStatus.failure,
      ),
      (const UnknownFailure(), PreviewStatus.failure),
    ]) {
      test('${failure.runtimeType} shows ${status.name}', () async {
        generator.answer = (_) => Err(failure);
        final cubit = await ready();
        expect(cubit.state.status, status);
        expect(cubit.state.program, isNull);
        expect(telemetry.names, isEmpty);
      });
    }

    test('is asked again on Retry', () async {
      generator.answer = (_) => const Err(NetworkFailure());
      final cubit = await ready();
      generator.answer = (_) => Ok(first);
      await cubit.retry();
      expect(cubit.state.status, PreviewStatus.ready);
      expect(generator.requests, hasLength(2));
    });

    test('of Regenerate asks again with its seed and kept items', () async {
      final cubit = await ready();
      cubit.toggleKept(1, 0);
      generator.answer = (_) => const Err(NetworkFailure());
      await cubit.regenerate();
      expect(cubit.state.status, PreviewStatus.offline);
      generator.answer = (_) => Ok(first);
      await cubit.retry();
      final request = generator.requests.last;
      expect(request.seed, 1);
      expect(request.kept, [
        <ProgramItem>[],
        [item('row')],
      ]);
    });
  });

  test('without Premium on the server asks again after 2, 4 and 8 s', () {
    fakeAsync((async) {
      generator.answer = (_) =>
          const Err(GenerationRefused(GenerationRefusal.notPremium, ''));
      final cubit = build();
      async.flushMicrotasks();
      expect(generator.requests, hasLength(1));
      expect(cubit.state.status, PreviewStatus.building);

      for (final (wait, asked) in [(2, 2), (4, 3), (8, 4)]) {
        async.elapse(Duration(seconds: wait) - const Duration(milliseconds: 1));
        expect(generator.requests, hasLength(asked - 1));
        async.elapse(const Duration(milliseconds: 1));
        expect(generator.requests, hasLength(asked));
      }
      expect(cubit.state.status, PreviewStatus.notPremium);
      async.elapse(const Duration(minutes: 1));
      expect(generator.requests, hasLength(4));

      // Retry starts over, and the server now sees Premium.
      generator.answer = (_) => Ok(first);
      unawaited(cubit.retry());
      async.flushMicrotasks();
      expect(cubit.state.status, PreviewStatus.ready);
      unawaited(cubit.close());
      async.flushMicrotasks();
    });
  });

  test('Regenerate sends the next seed and the kept items per day', () async {
    final cubit = await ready();
    cubit
      ..toggleKept(0, 1)
      ..editItem(0, 1, (item) => item.copyWith(sets: 5));
    final second = generated([
      ['bench', 'row'],
      ['squat'],
    ]);
    generator.answer = (_) => Ok(second);
    await cubit.regenerate();
    final request = generator.requests.last;
    expect(request.seed, 1);
    expect(request.kept, [
      [item('bench', sets: 5)],
      <ProgramItem>[],
    ]);
    expect(cubit.state.seed, 1);
    expect(cubit.state.program, second);
    // Still kept where it came back.
    expect(cubit.state.kept, {(0, 'bench')});
  });

  group('editing', () {
    test('a swap keeps sets, rest, group and the kept mark', () async {
      final cubit = await ready();
      cubit
        ..toggleKept(0, 0)
        ..swapItem(0, 0, 'raise');
      final swapped = cubit.state.program!.days.first.items.first;
      expect(swapped, item('raise'));
      expect(cubit.state.kept, {(0, 'raise')});
      // An exercise already on the day is not added again.
      cubit.swapItem(0, 0, 'bench');
      expect(cubit.state.program!.days.first.items.first.exerciseId, 'raise');
    });

    test('recount the uncovered muscles the server named', () async {
      final cubit = await ready();
      expect(cubit.state.uncovered, {Muscle.calf, Muscle.biceps});
      cubit.swapItem(0, 0, 'raise');
      expect(cubit.state.uncovered, {Muscle.biceps});
      cubit.swapItem(0, 0, 'squat');
      expect(cubit.state.uncovered, {Muscle.calf, Muscle.biceps});
    });

    test(
      'a removed item leaves the weekly sets; a day keeps its last',
      () async {
        final cubit = await ready();
        expect(cubit.volume!.sets[Muscle.quads], 3);
        cubit.removeItem(0, 0);
        expect(cubit.state.program!.days.first.items, [item('bench')]);
        expect(cubit.volume!.sets[Muscle.quads], isNull);
        cubit.removeItem(0, 0);
        expect(cubit.state.program!.days.first.items, [item('bench')]);
      },
    );

    test('a removed item dissolves a group left with one', () async {
      generator.answer = (_) => Ok(
        first.withDays([
          ProgramDay(
            name: 'A',
            items: [
              item('squat').withGroup('A'),
              item('bench').withGroup('A'),
              item('row'),
            ],
          ),
        ]),
      );
      final cubit = await ready();
      cubit.removeItem(0, 0);
      expect(cubit.state.program!.days.first.items, [
        item('bench'),
        item('row'),
      ]);
    });
  });

  group('saving', () {
    test('stores a generated program with the name given', () async {
      final cubit = await ready();
      await cubit.save(name: 'Full body, 2 days');
      expect(cubit.state.saveStatus, SaveStatus.saved);
      expect(cubit.state.savedId, 'p9');
      final saved =
          verify(() => programs.createProgram('u1', captureAny()))
                  .captured
                  .single
              as Program;
      expect(saved, first.toProgram(name: 'Full body, 2 days'));
      // Saved once only.
      await cubit.save(name: 'Again');
      verifyNever(() => programs.createProgram(any(), any()));
    });

    test('reports a failure, then lets the user try again', () async {
      when(() => programs.createProgram('u1', any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      final cubit = await ready();
      await cubit.save(name: 'Mine');
      expect(cubit.state.saveStatus, SaveStatus.failed);
      expect(cubit.state.saveFailure, isA<NetworkFailure>());
      cubit.saveFailureShown();
      expect(cubit.state.saveStatus, SaveStatus.idle);
      expect(cubit.state.program, first);
    });

    test('refuses exercises gone from the library', () async {
      final cubit = await ready();
      when(() => catalogue.state).thenReturn(
        CatalogueReady([
          for (final e in library)
            if (e.id != 'squat') e,
        ]),
      );
      await cubit.save(name: 'Mine');
      expect(cubit.state.saveFailure, isA<ValidationFailure>());
      verifyNever(() => programs.createProgram(any(), any()));
    });

    test('says why while nobody is signed in', () async {
      final cubit = build(user: null);
      addTearDown(cubit.close);
      await pumpEventQueue();
      await cubit.save(name: 'Mine');
      expect(cubit.state.saveFailure, isA<AuthFailure>());
    });

    test('says why while the library reloads', () async {
      final cubit = await ready();
      when(() => catalogue.state).thenReturn(const CatalogueLoading());
      await cubit.save(name: 'Mine');
      expect(cubit.state.saveFailure, isA<NotFoundFailure>());
    });
  });
}

/// A repository whose one answer comes when [_result] completes.
class _Deferred implements GeneratorRepository {
  _Deferred(this._result);

  final Future<Result<GeneratedProgram>> _result;

  @override
  Future<Result<GeneratedProgram>> generate(GenerationRequest request) =>
      _result;

  @override
  Stream<Never> watchOptions() => const Stream.empty();
}
