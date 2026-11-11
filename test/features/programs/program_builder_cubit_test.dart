import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/domain/program_validation.dart';
import 'package:get_workout/features/programs/presentation/program_builder_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

class MockExerciseRepository extends Mock implements ExerciseRepository {}

void main() {
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  final catalogue = [
    for (final id in ['a', 'b', 'c', 'd']) move(id),
    move('plank', type: LoggingType.duration, rest: 45),
    move('pushup', type: LoggingType.reps, rest: 60),
  ];
  Exercise byId(String id) => catalogue.firstWhere((e) => e.id == id);

  late MockAuthRepository auth;
  late MockProgramRepository repository;
  late StreamController<AuthUser?> users;
  late StreamController<List<Exercise>> exercises;
  late ExerciseCatalogueCubit catalogueCubit;

  setUpAll(() => registerFallbackValue(program()));

  setUp(() {
    auth = MockAuthRepository();
    repository = MockProgramRepository();
    users = StreamController<AuthUser?>.broadcast();
    exercises = StreamController<List<Exercise>>.broadcast();
    when(() => auth.currentUser).thenReturn(member);
    Stream<AuthUser?> watchUser() async* {
      yield member;
      yield* users.stream;
    }

    when(() => auth.watchUser()).thenAnswer((_) => watchUser());
    when(() => repository.createProgram(any(), any()))
        .thenAnswer((_) async => const Ok('new'));
    when(() => repository.updateProgram(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    final exerciseRepository = MockExerciseRepository();
    when(exerciseRepository.watchExercises).thenAnswer((_) => exercises.stream);
    final idle = MockAuthRepository();
    when(idle.watchUser).thenAnswer((_) => const Stream.empty());
    catalogueCubit = ExerciseCatalogueCubit(
      watchAuthUser: WatchAuthUser(idle),
      watchExercises: WatchExercises(exerciseRepository),
      syncExercises: SyncExercises(exerciseRepository),
    );
  });

  tearDown(() => catalogueCubit.close());

  Future<ProgramBuilderCubit> build({
    String? programId,
    WeightUnit unit = WeightUnit.kg,
    bool catalogueReady = true,
  }) async {
    final cubit = ProgramBuilderCubit(
      programId: programId,
      getProgram: GetProgram(repository),
      saveProgram: SaveProgram(repository),
      getCurrentUser: GetCurrentUser(auth),
      watchAuthUser: WatchAuthUser(auth),
      catalogue: catalogueCubit,
      weightUnit: unit,
    );
    addTearDown(cubit.close);
    if (catalogueReady) exercises.add(catalogue);
    await pumpEventQueue();
    return cubit;
  }

  /// A new program named "Push" whose only day has [ids].
  Future<ProgramBuilderCubit> filled(List<String> ids) async {
    final cubit = await build();
    cubit
      ..setName('Push')
      ..addExercises([for (final id in ids) byId(id)]);
    return cubit;
  }

  group('a new program', () {
    test('starts with one empty day and no changes', () async {
      final cubit = await build();
      expect(cubit.state.status, ProgramBuilderStatus.editing);
      expect(
        cubit.state.program,
        const Program(name: '', days: [ProgramDay()]),
      );
      expect(cubit.state.dirty, isFalse);
      expect(cubit.state.catalogueReady, isTrue);
      expect(cubit.isEditing, isFalse);
    });

    test('is dirty while it differs from what it started as', () async {
      final cubit = await build();
      cubit.setName('Push');
      expect(cubit.state.dirty, isTrue);
      cubit.setName('');
      expect(cubit.state.dirty, isFalse);
    });

    test('a blank length is none, a number is weeks', () async {
      final cubit = await build();
      cubit.setLengthWeeks('8');
      expect(cubit.state.program.lengthWeeks, 8);
      cubit.setLengthWeeks(' ');
      expect(cubit.state.program.lengthWeeks, isNull);
    });
  });

  group('editing a stored program', () {
    test('loads it', () async {
      when(() => repository.getProgram('u1', 'p1'))
          .thenAnswer((_) async => Ok(program(id: 'p1')));
      final cubit = await build(programId: 'p1');
      expect(cubit.state.status, ProgramBuilderStatus.editing);
      expect(cubit.state.program, program(id: 'p1'));
      expect(cubit.state.dirty, isFalse);
    });

    test('says when it no longer exists', () async {
      when(() => repository.getProgram('u1', 'p1'))
          .thenAnswer((_) async => const Err(NotFoundFailure()));
      final cubit = await build(programId: 'p1');
      expect(cubit.state.status, ProgramBuilderStatus.notFound);
    });

    test('a failed load can be retried', () async {
      var calls = 0;
      when(() => repository.getProgram('u1', 'p1')).thenAnswer(
        (_) async =>
            ++calls == 1 ? const Err(NetworkFailure()) : Ok(program(id: 'p1')),
      );
      final cubit = await build(programId: 'p1');
      expect(cubit.state.status, ProgramBuilderStatus.loadFailed);
      cubit.setName('ignored while not loaded');
      expect(cubit.state.status, ProgramBuilderStatus.loadFailed);
      await cubit.load();
      expect(cubit.state.status, ProgramBuilderStatus.editing);
      expect(cubit.state.program.name, 'Upper Lower');
    });

    test('saving updates it and keeps its id', () async {
      when(() => repository.getProgram('u1', 'p1'))
          .thenAnswer((_) async => Ok(program(id: 'p1')));
      final cubit = await build(programId: 'p1');
      cubit.setName('Upper Lower 2');
      await cubit.save();
      expect(cubit.state.status, ProgramBuilderStatus.saved);
      expect(cubit.state.savedId, 'p1');
      expect(cubit.state.dirty, isFalse);
      verify(
        () => repository.updateProgram(
          'u1',
          program(id: 'p1', name: 'Upper Lower 2'),
        ),
      ).called(1);
    });
  });

  group('days', () {
    test('a new day is added and selected, up to seven', () async {
      final cubit = await build();
      for (var i = 0; i < 8; i++) {
        cubit.addDay();
      }
      expect(cubit.state.program.days, hasLength(7));
      expect(cubit.state.selectedDay, 6);
      expect(cubit.state.canAddDay, isFalse);
    });

    test('rename, move and delete', () async {
      final cubit = await build();
      cubit
        ..renameDay(0, 'Push')
        ..addDay()
        ..renameDay(1, 'Pull')
        ..addDay()
        ..renameDay(2, 'Legs')
        ..moveDay(2, 0);
      List<String> names() => [
        for (final d in cubit.state.program.days) d.name,
      ];
      expect(names(), ['Legs', 'Push', 'Pull']);
      expect(cubit.state.selectedDay, 0);

      cubit
        ..selectDay(2)
        ..deleteDay(0);
      expect(names(), ['Push', 'Pull']);
      expect(cubit.state.selectedDay, 1, reason: 'Pull stays selected');
      cubit.deleteDay(1);
      expect(cubit.state.selectedDay, 0);
      cubit.deleteDay(0);
      expect(names(), ['Push'], reason: 'the last day stays');
    });
  });

  group('items', () {
    test('exercises are added with their defaults', () async {
      final cubit = await filled(['a', 'plank']);
      expect(cubit.state.day!.items, [
        const ProgramItem(
          exerciseId: 'a',
          sets: 3,
          repMin: 8,
          repMax: 12,
          restS: 90,
        ),
        const ProgramItem(
          exerciseId: 'plank',
          sets: 3,
          durationS: 30,
          restS: 45,
        ),
      ]);
    });

    test('a day takes at most 20 items', () async {
      final cubit = await filled([for (var i = 0; i < 19; i++) 'a']);
      expect(cubit.state.freeSlots, 1);
      cubit.addExercises([byId('b'), byId('c')]);
      expect(cubit.state.day!.items, hasLength(20));
      expect(cubit.state.day!.items.last.exerciseId, 'b');
      expect(cubit.state.freeSlots, 0);
    });

    test('items go to the selected day', () async {
      final cubit = await filled(['a']);
      cubit
        ..addDay()
        ..addExercises([byId('b')]);
      expect(cubit.state.program.days[0].items.single.exerciseId, 'a');
      expect(cubit.state.program.days[1].items.single.exerciseId, 'b');
    });

    test('fields are typed as text', () async {
      final cubit = await filled(['a', 'plank']);
      cubit
        ..setSets(0, '5')
        ..setRepMin(0, '3')
        ..setRepMax(0, ' 5 ')
        ..setRest(0, '180')
        ..setDuration(1, '60');
      expect(
        cubit.state.day!.items[0],
        const ProgramItem(
          exerciseId: 'a',
          sets: 5,
          repMin: 3,
          repMax: 5,
          restS: 180,
        ),
      );
      expect(cubit.state.day!.items[1].durationS, 60);
      cubit
        ..setSets(0, '')
        ..setRepMin(0, '')
        ..setRest(0, '');
      expect(cubit.state.day!.items[0].sets, 0);
      expect(cubit.state.day!.items[0].repMin, isNull);
      expect(cubit.state.day!.items[0].restS, 0);
      expect(cubit.state.liveItemIssues(0), {
        ItemIssue.setsOutOfRange,
        ItemIssue.repsMissing,
      });
    });

    test('the target is typed in the user\'s unit and stored in kg', () async {
      final cubit = await build(unit: WeightUnit.lb);
      cubit
        ..addExercises([byId('a')])
        ..setTarget(0, '100');
      expect(cubit.state.day!.items[0].targetKg, closeTo(45.359, 0.001));
      cubit.setTarget(0, '22,5');
      expect(cubit.state.day!.items[0].targetKg, closeTo(10.206, 0.001));
      cubit.setTarget(0, '');
      expect(cubit.state.day!.items[0].targetKg, isNull);
    });

    test('supersets, circuits, moves and removals', () async {
      final cubit = await filled(['a', 'b', 'c', 'd']);
      List<String?> groups() => [
        for (final i in cubit.state.day!.items) i.group,
      ];
      List<String> ids() => [
        for (final i in cubit.state.day!.items) i.exerciseId,
      ];

      cubit.linkWithNext(0);
      expect(groups(), ['A', 'A', null, null]);
      cubit.linkWithNext(1);
      expect(groups(), ['A', 'A', 'A', null]);
      cubit.linkWithNext(3);
      expect(groups(), ['A', 'A', 'A', null], reason: 'nothing follows');
      cubit.moveItem(3, 0);
      expect(ids(), ['d', 'a', 'b', 'c']);
      cubit.ungroup(2);
      expect(groups(), [null, null, null, null]);
      cubit.removeItem(0);
      expect(ids(), ['a', 'b', 'c']);
    });
  });

  group('saving', () {
    test('a valid new program is created with its name trimmed', () async {
      final cubit = await filled(['a']);
      cubit.setName('  Push  ');
      await cubit.save();
      expect(cubit.state.status, ProgramBuilderStatus.saved);
      expect(cubit.state.savedId, 'new');
      verify(
        () => repository.createProgram(
          'u1',
          Program(
            name: 'Push',
            days: [
              ProgramDay(items: [defaultFor('a')]),
            ],
          ),
        ),
      ).called(1);
    });

    test('an invalid program shows its issues and is not saved', () async {
      final cubit = await build();
      cubit
        ..addDay()
        ..addExercises([byId('a')])
        ..setSets(0, '11');
      expect(cubit.state.validation.isValid, isTrue, reason: 'not yet shown');
      await cubit.save();
      expect(cubit.state.status, ProgramBuilderStatus.editing);
      expect(cubit.state.validation.program, {ProgramIssue.nameMissing});
      expect(cubit.state.validation.dayIssues(0), {DayIssue.noItems});
      expect(cubit.state.validation.itemIssues(1, 0), {
        ItemIssue.setsOutOfRange,
      });
      verifyNever(() => repository.createProgram(any(), any()));

      // Once shown, the issues follow every edit.
      cubit.setName('Push');
      expect(cubit.state.validation.program, isEmpty);
    });

    test('with only day issues, the first day with one is selected', () async {
      final cubit = await filled(['a']);
      cubit
        ..addDay()
        ..addDay()
        ..addExercises([byId('b')])
        ..selectDay(2);
      await cubit.save();
      expect(cubit.state.selectedDay, 1);
    });

    test('a failed save is reported and can be repeated', () async {
      when(() => repository.createProgram(any(), any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      final cubit = await filled(['a']);
      await cubit.save();
      expect(cubit.state.status, ProgramBuilderStatus.saveFailed);
      expect(cubit.state.failure, const NetworkFailure());
      expect(cubit.state.dirty, isTrue);
    });

    test('waits for the catalogue', () async {
      final cubit = await build(catalogueReady: false);
      cubit.setName('Push');
      await cubit.save();
      expect(cubit.state.status, ProgramBuilderStatus.editing);
      verifyNever(() => repository.createProgram(any(), any()));
    });
  });

  group('unavailable exercises', () {
    final withRetired = Program(
      id: 'p1',
      name: 'Old',
      days: [
        ProgramDay(
          items: [
            item('a', group: 'A'),
            item('retired', sets: 4, group: 'A'),
          ],
        ),
      ],
    );

    setUp(() {
      when(() => repository.getProgram('u1', 'p1'))
          .thenAnswer((_) async => Ok(withRetired));
    });

    test(
      'still load, and show as unavailable once the catalogue is known',
      () async {
        final cubit = await build(programId: 'p1', catalogueReady: false);
        expect(cubit.state.program, withRetired);
        final retired = cubit.state.day!.items[1];
        expect(cubit.state.isUnavailable(retired), isFalse);
        exercises.add(catalogue);
        await pumpEventQueue();
        expect(cubit.state.isUnavailable(retired), isTrue);
        expect(cubit.state.isUnavailable(cubit.state.day!.items[0]), isFalse);
      },
    );

    test('block saving until replaced', () async {
      final cubit = await build(programId: 'p1');
      await cubit.save();
      expect(cubit.state.validation.itemIssues(0, 1), {
        ItemIssue.exerciseUnavailable,
      });
      verifyNever(() => repository.updateProgram(any(), any()));

      cubit.replaceExercise(1, byId('pushup'));
      expect(cubit.state.day!.items[1], item('pushup', sets: 4, group: 'A'));
      await cubit.save();
      expect(cubit.state.status, ProgramBuilderStatus.saved);
    });

    test('or removed, which also dissolves their superset', () async {
      final cubit = await build(programId: 'p1');
      cubit.removeItem(1);
      expect(cubit.state.day!.items, [item('a')]);
      await cubit.save();
      expect(cubit.state.status, ProgramBuilderStatus.saved);
    });
  });

  group('items that no longer fit their exercise', () {
    // 'a' logs weight and reps, 'plank' a duration; an admin changed both.
    final stale = Program(
      id: 'p1',
      name: 'Old',
      days: [
        ProgramDay(
          items: [
            item('a', repMin: null, repMax: null, durationS: 45),
            item('plank', targetKg: 20),
            item('b'),
          ],
        ),
      ],
    );

    setUp(() {
      when(() => repository.getProgram('u1', 'p1'))
          .thenAnswer((_) async => Ok(stale));
    });

    void expectFitted(ProgramBuilderCubit cubit) {
      expect(cubit.state.day!.items, [
        item('a'),
        item('plank', repMin: null, repMax: null, durationS: 30),
        item('b'),
      ]);
      expect(cubit.state.adjusted, unorderedEquals(['a', 'plank']));
      expect(cubit.state.dirty, isTrue);
    }

    test('are fitted on load and reported once', () async {
      final cubit = await build(programId: 'p1');
      expectFitted(cubit);
      cubit.adjustedShown();
      expect(cubit.state.adjusted, isEmpty);
      await cubit.save();
      expect(cubit.state.status, ProgramBuilderStatus.saved);
    });

    test('also when the catalogue arrives after the program', () async {
      final cubit = await build(programId: 'p1', catalogueReady: false);
      expect(cubit.state.program, stale);
      exercises.add(catalogue);
      await pumpEventQueue();
      expectFitted(cubit);
    });

    test('a program that fits is left as stored', () async {
      when(() => repository.getProgram('u1', 'p1'))
          .thenAnswer((_) async => Ok(program(id: 'p1')));
      final cubit = await build(programId: 'p1');
      expect(cubit.state.adjusted, isEmpty);
      expect(cubit.state.dirty, isFalse);
    });
  });

  test('closes when the user changes and then ignores edits', () async {
    final cubit = await filled(['a']);
    when(() => auth.currentUser).thenReturn(null);
    users.add(const AuthUser(id: 'g2', isAnonymous: true));
    await pumpEventQueue();
    expect(cubit.state.status, ProgramBuilderStatus.closed);
    final closed = cubit.state;
    cubit.setName('Other');
    await cubit.save();
    expect(cubit.state, closed);
    verifyNever(() => repository.createProgram(any(), any()));
  });
}

/// The default item of exercise `a`, a weighted rep exercise resting 90 s.
ProgramItem defaultFor(String id) =>
    ProgramItem(exerciseId: id, sets: 3, repMin: 8, repMax: 12, restS: 90);
