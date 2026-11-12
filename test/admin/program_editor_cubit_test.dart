import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/access/domain/access_usecases.dart';
import 'package:get_workout/admin/access/domain/admin_access_repository.dart';
import 'package:get_workout/admin/exercises/domain/admin_exercise_repository.dart';
import 'package:get_workout/admin/exercises/domain/exercise_admin_usecases.dart';
import 'package:get_workout/admin/exercises/domain/exercise_draft.dart';
import 'package:get_workout/admin/programs/domain/admin_program_repository.dart';
import 'package:get_workout/admin/programs/domain/program_admin_usecases.dart';
import 'package:get_workout/admin/programs/domain/program_draft.dart';
import 'package:get_workout/admin/programs/presentation/program_editor_cubit.dart';
import 'package:get_workout/admin/shell/editor_status.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/catalogue_program.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:mocktail/mocktail.dart';

import 'program_fixtures.dart';

class MockProgramRepository extends Mock implements AdminProgramRepository {}

class MockExerciseRepository extends Mock implements AdminExerciseRepository {}

class MockAccessRepository extends Mock implements AdminAccessRepository {}

void main() {
  late MockProgramRepository repository;
  late MockExerciseRepository exerciseRepository;
  late MockAccessRepository access;
  late StreamController<List<ProgramRecord>> cards;
  late StreamController<List<ExerciseRecord>> library;

  const id = 'pr_dumbbell_basics';
  final loadedAt = DateTime.utc(2026, 11, 1);
  final savedAt = DateTime.utc(2026, 11, 2);
  final basics = programRecord(programJson(), card: loadedAt, detail: loadedAt);
  final other = programRecord(
    cardOf(programJson(id: 'pr_other', name: 'Other', order: 2)),
  );

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue((card: null, detail: null) as ProgramVersion);
  });

  setUp(() {
    repository = MockProgramRepository();
    exerciseRepository = MockExerciseRepository();
    access = MockAccessRepository();
    when(() => access.claims(refresh: true))
        .thenAnswer((_) async => const Ok({'admin': true}));
    cards = StreamController();
    library = StreamController();
    when(() => repository.watchCards()).thenAnswer((_) => cards.stream);
    when(() => exerciseRepository.watchAll()).thenAnswer((_) => library.stream);
    when(() => repository.load(id)).thenAnswer((_) async => Ok(basics));
    // A save stores the content as given.
    Future<Result<ProgramSaveOutcome>> saved(Invocation call) async => Ok(
      ProgramSaved(
        programRecord(
          call.positionalArguments.first as Map<String, Object?>,
          card: savedAt,
          detail: savedAt,
        ),
      ),
    );
    when(() => repository.create(any())).thenAnswer(saved);
    when(() => repository.update(any(), loaded: any(named: 'loaded')))
        .thenAnswer(saved);
  });

  Future<ProgramEditorCubit> open(
    String? programId, {
    bool catalogueLoads = true,
  }) async {
    final cubit = ProgramEditorCubit(
      id: programId,
      loadProgramRecord: LoadProgramRecord(repository),
      watchProgramCards: WatchProgramCards(repository),
      watchExerciseRecords: WatchExerciseRecords(exerciseRepository),
      createProgram: CreateProgram(repository),
      updateProgram: UpdateProgram(repository),
      checkAdminAccess: CheckAdminAccess(access),
    );
    addTearDown(cubit.close);
    if (catalogueLoads) {
      cards.add([programRecord(cardOf(programJson())), other]);
    }
    library.add(exerciseRecords);
    await pumpEventQueue();
    return cubit;
  }

  group('create', () {
    test('starts empty, with the id editable', () async {
      final cubit = await open(null);
      expect(cubit.state.isNew, isTrue);
      expect(cubit.state.status, EditorStatus.editing);
      expect(cubit.state.draft, const ProgramDraft());
      expect(cubit.state.entries.keys, contains('ex_curl'));
      verifyNever(() => repository.load(any()));
    });

    test('reports problems by field and writes nothing', () async {
      final cubit = await open(null);
      cubit.change(
        (d) => d
            .copyWith(id: 'Bad Id', order: 2)
            .withText(
              'en',
              const CatalogueText(name: 'Other', summary: 'Short. Plan.'),
            ),
      );

      await cubit.save();

      final state = cubit.state;
      expect(state.status, EditorStatus.editing);
      expect(state.problemsFor('id'), [contains('id must match')]);
      expect(state.problemsFor('level'), isNotEmpty);
      expect(state.problemsFor('days'), isNotEmpty);
      expect(state.problemsFor('catalogue'), [
        'name "other" also used by pr_other',
        'order "2" also used by pr_other',
      ]);
      verifyNever(() => repository.create(any()));
    });

    test('an id already in the catalogue is refused', () async {
      final cubit = await open(null);
      cubit.change((_) => ProgramDraft.fromJson(programJson(order: 3)));
      await cubit.save();
      expect(cubit.state.problemsFor('id'), [
        'id "pr_dumbbell_basics" is already used',
      ]);
    });

    test('saves a valid program, card and days as one content', () async {
      final cubit = await open(null);
      final json = programJson(id: 'pr_new', name: 'New', order: 3);
      cubit.change((_) => ProgramDraft.fromJson(json));

      await cubit.save();

      verify(() => repository.create(json)).called(1);
      expect(cubit.state.status, EditorStatus.saved);
      expect(cubit.state.isNew, isFalse);
      expect(cubit.state.loaded?.version.card, savedAt);
    });

    test(
      'an id taken on the server meanwhile is a problem on the id',
      () async {
        when(() => repository.create(any()))
            .thenAnswer((_) async => const Ok(ProgramIdTaken()));
        final cubit = await open(null);
        cubit.change(
          (_) => ProgramDraft.fromJson(
            programJson(id: 'pr_new', name: 'New', order: 3),
          ),
        );
        await cubit.save();
        expect(cubit.state.problemsFor('id'), ['id "pr_new" is already used']);
        expect(cubit.state.isNew, isTrue);
      },
    );
  });

  group('edit', () {
    test('loads the stored program', () async {
      final cubit = await open(id);
      expect(cubit.state.isNew, isFalse);
      expect(cubit.state.draft, basics.draft);
      expect(cubit.state.isDirty, isFalse);
      expect(cubit.state.canSave(), isFalse);
      expect(cubit.state.canSave(ExerciseStatus.retired), isTrue);
    });

    test('saves with the version it loaded, then the saved one', () async {
      final cubit = await open(id);
      cubit.change((d) => d.copyWith(premium: true));
      await cubit.save();
      cubit.change((d) => d.copyWith(lengthWeeks: 12));
      await cubit.save();

      verify(
        () => repository.update(
          programJson(premium: true),
          loaded: (card: loadedAt, detail: loadedAt),
        ),
      ).called(1);
      verify(
        () =>
            repository.update(any(), loaded: (card: savedAt, detail: savedAt)),
      ).called(1);
      expect(cubit.state.status, EditorStatus.saved);
      expect(cubit.state.isDirty, isFalse);
    });

    test('an exercise that is not live blocks the save', () async {
      final cubit = await open(id);
      cubit.addExercise(0, 'ex_old_press');
      await cubit.saveAs(ExerciseStatus.live);
      expect(cubit.state.problemsWithin('days[0]'), [
        contains('not a live exercise'),
      ]);
      verifyNever(() => repository.update(any(), loaded: any(named: 'loaded')));
    });

    test('problems follow the draft after a failed save', () async {
      final cubit = await open(id);
      cubit.change((d) => d.copyWith(level: null));
      await cubit.save();
      expect(cubit.state.problemsFor('level'), isNotEmpty);
      cubit.change((d) => d.copyWith(level: Level.beginner));
      expect(cubit.state.problems, isEmpty);
    });

    test('warnings and computed fields follow the days', () async {
      final cubit = await open(id);
      expect(cubit.state.content['daysPerWeek'], 2);
      expect(cubit.state.warnings, contains(startsWith('quads gets 0')));
      cubit.removeDay(1);
      expect(cubit.state.content['daysPerWeek'], 1);
      expect(cubit.state.summary.minutesPerDay, hasLength(1));
    });
  });

  group('days and items', () {
    test(
      'adding an exercise uses its defaults and rebuilds the form',
      () async {
        final cubit = await open(id);
        final version = cubit.state.formVersion;
        cubit.addExercise(0, 'ex_curl');
        expect(
          cubit.state.draft.days[0].items.last,
          const ProgramItem(
            exerciseId: 'ex_curl',
            sets: 3,
            repMin: 8,
            repMax: 12,
            restS: 90,
          ),
        );
        expect(cubit.state.formVersion, version + 1);
      },
    );

    test('typing into a field keeps the form', () async {
      final cubit = await open(id);
      final version = cubit.state.formVersion;
      cubit.changeItem(0, 0, (item) => item.copyWith(sets: 4));
      cubit.renameDay(0, 'Push');
      expect(cubit.state.draft.days[0].items[0].sets, 4);
      expect(cubit.state.draft.days[0].name, 'Push');
      expect(cubit.state.formVersion, version);
    });

    test('days are added, moved and removed', () async {
      final cubit = await open(id);
      List<String> names() => [for (final d in cubit.state.draft.days) d.name];
      cubit.moveDay(1, 0);
      expect(names(), ['Day B', 'Day A']);
      cubit.addDay();
      expect(names(), ['Day B', 'Day A', '']);
      cubit.removeDay(0);
      expect(names(), ['Day A', '']);
    });

    test('items are grouped, moved and removed as the builder does', () async {
      final cubit = await open(id);
      List<String?> groups(int day) => [
        for (final item in cubit.state.draft.days[day].items) item.group,
      ];
      cubit.linkWithNext(0, 0);
      expect(groups(0), ['A', 'A']);
      cubit.ungroup(1, 0);
      expect(groups(1), [null, null]);
      cubit.moveItem(1, 0, 1);
      expect(
        cubit.state.draft.days[1].items.first.exerciseId,
        'ex_dumbbell_press',
      );
      cubit.removeItem(0, 0);
      expect(groups(0), [null]);
    });
  });

  test('nothing is saved until the other programs have loaded', () async {
    final cubit = await open(null, catalogueLoads: false);
    cubit.change(
      (_) => ProgramDraft.fromJson(
        programJson(id: 'pr_new', name: 'New', order: 2),
      ),
    );

    await cubit.save();

    expect(cubit.state.problems, [ProgramEditorCubit.catalogueNotLoaded]);
    verifyNever(() => repository.create(any()));
    // Once they arrive, the clash they reveal replaces the wait.
    cards.add([other]);
    await pumpEventQueue();
    expect(cubit.state.problemsFor('catalogue'), [
      'order "2" also used by pr_other',
    ]);
  });

  test(
    'a save overtaken by another before it was read back is not adopted',
    () async {
      final overtaking = programRecord(
        programJson(order: 9),
        card: savedAt,
        detail: savedAt,
      );
      when(() => repository.update(any(), loaded: any(named: 'loaded')))
          .thenAnswer((_) async => Ok(ProgramSaved(overtaking)));
      final cubit = await open(id);
      cubit.change((d) => d.copyWith(premium: true));

      await cubit.save();

      expect(cubit.state.status, EditorStatus.changedSinceLoaded);
      expect(cubit.state.draft.premium, isTrue);
      expect(cubit.state.loaded, isNot(overtaking));

      // Saving again checks the stored program first, and is refused.
      when(() => repository.load(id)).thenAnswer((_) async => Ok(overtaking));
      cubit.change((d) => d.copyWith(lengthWeeks: 12));
      await cubit.save();
      expect(cubit.state.status, EditorStatus.changedSinceLoaded);
      verify(() => repository.update(any(), loaded: any(named: 'loaded')))
          .called(1);
    },
  );

  test('a program changed since loading is refused, then reloaded', () async {
    when(() => repository.update(any(), loaded: any(named: 'loaded')))
        .thenAnswer((_) async => const Ok(ProgramChangedSinceLoaded()));
    final cubit = await open(id);
    cubit.change((d) => d.copyWith(premium: true));

    await cubit.save();
    expect(cubit.state.status, EditorStatus.changedSinceLoaded);
    cubit.change((d) => d.copyWith(order: 5));
    expect(cubit.state.status, EditorStatus.changedSinceLoaded);

    final newer = programRecord(
      programJson(order: 9),
      card: DateTime.utc(2026, 11, 3),
    );
    when(() => repository.load(id)).thenAnswer((_) async => Ok(newer));
    final version = cubit.state.formVersion;
    await cubit.reload();

    expect(cubit.state.status, EditorStatus.editing);
    expect(cubit.state.draft, newer.draft);
    expect(cubit.state.formVersion, version + 1);
  });

  test('a denied write refreshes the token to tell why', () async {
    when(() => repository.update(any(), loaded: any(named: 'loaded')))
        .thenAnswer((_) async => const Err(PermissionFailure()));
    final cubit = await open(id);
    cubit.change((d) => d.copyWith(premium: true));

    await cubit.save();

    expect(cubit.state.status, EditorStatus.saveFailed);
    expect(cubit.state.failure, isA<PermissionFailure>());
    verify(() => access.claims(refresh: true)).called(1);
    expect(cubit.state.accessRefreshed, isTrue);
  });

  group('a save whose new version could not be read', () {
    setUp(
      () =>
          when(() => repository.update(any(), loaded: any(named: 'loaded')))
              .thenAnswer((_) async => const Ok(ProgramSaved(null))),
    );

    test('reads the stored program before the next save', () async {
      final cubit = await open(id);
      cubit.change((d) => d.copyWith(premium: true));
      await cubit.save();
      expect(cubit.state.status, EditorStatus.saved);
      expect(cubit.state.isDirty, isFalse);

      final stored = programRecord(
        programJson(premium: true),
        card: savedAt,
        detail: savedAt,
      );
      when(() => repository.load(id)).thenAnswer((_) async => Ok(stored));
      cubit.change((d) => d.copyWith(order: 5));
      await cubit.save();

      verify(
        () =>
            repository.update(any(), loaded: (card: savedAt, detail: savedAt)),
      ).called(1);
    });

    test('is refused when someone changed it since', () async {
      final cubit = await open(id);
      cubit.change((d) => d.copyWith(premium: true));
      await cubit.save();
      when(() => repository.load(id)).thenAnswer(
        (_) async => Ok(programRecord(programJson(order: 9), card: savedAt)),
      );
      cubit.change((d) => d.copyWith(order: 5));

      await cubit.save();

      expect(cubit.state.status, EditorStatus.changedSinceLoaded);
    });
  });
}
