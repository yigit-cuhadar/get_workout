import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/exercises/domain/admin_exercise_repository.dart';
import 'package:get_workout/admin/exercises/domain/exercise_admin_usecases.dart';
import 'package:get_workout/admin/exercises/domain/exercise_draft.dart';
import 'package:get_workout/admin/exercises/presentation/exercise_editor_cubit.dart';
import 'package:get_workout/admin/shell/admin_text.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockRepository extends Mock implements AdminExerciseRepository {}

void main() {
  late MockRepository repository;
  late StreamController<List<ExerciseRecord>> library;

  final loadedAt = DateTime.utc(2026, 11, 1);
  final savedAt = DateTime.utc(2026, 11, 2);
  final press = record(validJson(), updatedAt: loadedAt);
  final curl = record(
    validJson(id: 'ex_curl', name: 'Curl', popularity: 2, family: 'curl'),
  );

  setUpAll(() => registerFallbackValue(const ExerciseDraft()));

  setUp(() {
    repository = MockRepository();
    library = StreamController();
    when(() => repository.watchAll()).thenAnswer((_) => library.stream);
    when(() => repository.load('ex_dumbbell_press'))
        .thenAnswer((_) async => Ok(press));
    // A save stores the draft as given.
    Future<Result<SaveOutcome>> saved(Invocation call) async => Ok(
      Saved(
        record(
          (call.positionalArguments.first as ExerciseDraft).toJson(),
          updatedAt: savedAt,
        ),
      ),
    );
    when(() => repository.create(any())).thenAnswer(saved);
    when(
      () => repository.update(
        any(),
        loadedUpdatedAt: any(named: 'loadedUpdatedAt'),
      ),
    ).thenAnswer(saved);
  });

  Future<ExerciseEditorCubit> open(String? id) async {
    final cubit = ExerciseEditorCubit(
      id: id,
      loadExerciseRecord: LoadExerciseRecord(repository),
      watchExerciseRecords: WatchExerciseRecords(repository),
      createExercise: CreateExercise(repository),
      updateExercise: UpdateExercise(repository),
    );
    addTearDown(cubit.close);
    library.add([press, curl]);
    await pumpEventQueue();
    return cubit;
  }

  group('create', () {
    test('starts empty, with the id editable', () async {
      final cubit = await open(null);
      expect(cubit.state.isNew, isTrue);
      expect(cubit.state.status, EditorStatus.editing);
      expect(cubit.state.draft, const ExerciseDraft());
      verifyNever(() => repository.load(any()));
    });

    test('reports problems by field and writes nothing', () async {
      final cubit = await open(null);
      cubit.change((d) => d.copyWith(id: 'Bad Id', name: 'Curl'));

      await cubit.save();

      final state = cubit.state;
      expect(state.status, EditorStatus.editing);
      expect(state.problemsFor('id'), [contains('id must match')]);
      expect(state.problemsFor('l10n.en.name'), [
        'name "Curl" also used by ex_curl',
      ]);
      expect(state.problemsFor('mainMuscles'), [
        'mainMuscles must have 1-2 items, has 0',
      ]);
      expect(state.problemsFor('loggingType'), isNotEmpty);
      verifyNever(() => repository.create(any()));
    });

    test('problems follow the draft after a failed save', () async {
      final cubit = await open(null);
      await cubit.save();
      expect(cubit.state.problemsFor('mainMuscles'), isNotEmpty);
      cubit.change((d) => d.copyWith(mainMuscles: [Muscle.pec]));
      expect(cubit.state.problemsFor('mainMuscles'), isEmpty);
      expect(cubit.state.problems, isNotEmpty);
    });

    test('an id already in the library is refused', () async {
      final cubit = await open(null);
      cubit.change((_) => ExerciseDraft.fromJson(validJson(name: 'New')));
      await cubit.save();
      expect(cubit.state.problemsFor('id'), [
        'id "ex_dumbbell_press" is already used',
      ]);
    });

    test('saves a valid exercise as a draft', () async {
      final cubit = await open(null);
      final draft = ExerciseDraft.fromJson(
        validJson(id: 'ex_new', name: 'New', status: 'draft'),
      );
      cubit.change((_) => draft);

      await cubit.save();

      verify(() => repository.create(draft)).called(1);
      expect(cubit.state.status, EditorStatus.saved);
      expect(cubit.state.isNew, isFalse);
      expect(cubit.state.loaded?.updatedAt, savedAt);
    });

    test(
      'an id taken on the server meanwhile is a problem on the id',
      () async {
        when(() => repository.create(any()))
            .thenAnswer((_) async => const Ok(IdTaken()));
        final cubit = await open(null);
        cubit.change(
          (_) => ExerciseDraft.fromJson(validJson(id: 'ex_new', name: 'New')),
        );
        await cubit.save();
        expect(cubit.state.problemsFor('id'), ['id "ex_new" is already used']);
        expect(cubit.state.isNew, isTrue);
      },
    );
  });

  group('edit', () {
    test('loads the stored document', () async {
      final cubit = await open('ex_dumbbell_press');
      expect(cubit.state.isNew, isFalse);
      expect(cubit.state.draft, press.draft);
      expect(cubit.state.loaded, press);
      expect(cubit.state.isDirty, isFalse);
    });

    test('a missing document fails to load', () async {
      when(() => repository.load('ex_gone'))
          .thenAnswer((_) async => const Err(NotFoundFailure()));
      final cubit = await open('ex_gone');
      expect(cubit.state.status, EditorStatus.loadFailed);
      expect(cubit.state.failure, isA<NotFoundFailure>());
    });

    test('saves with the updatedAt it loaded', () async {
      final cubit = await open('ex_dumbbell_press');
      cubit.change((d) => d.copyWith(popularity: 4));
      expect(cubit.state.isDirty, isTrue);

      await cubit.save();

      verify(
        () => repository.update(
          press.draft.copyWith(popularity: 4),
          loadedUpdatedAt: loadedAt,
        ),
      ).called(1);
      expect(cubit.state.status, EditorStatus.saved);
      expect(cubit.state.isDirty, isFalse);
    });

    test('the next save uses the updatedAt of the last one', () async {
      final cubit = await open('ex_dumbbell_press');
      await cubit.save();
      await cubit.save();
      verify(() => repository.update(any(), loadedUpdatedAt: savedAt))
          .called(1);
    });

    test('its own name is no conflict', () async {
      final cubit = await open('ex_dumbbell_press');
      await cubit.save();
      expect(cubit.state.problems, isEmpty);
    });

    test('pinned and excluded ids must exist and not be itself', () async {
      final cubit = await open('ex_dumbbell_press');
      cubit.change(
        (d) => d.copyWith(
          pinnedAlternatives: ['ex_curl', 'ex_missing'],
          excludedAlternatives: ['ex_dumbbell_press'],
        ),
      );
      await cubit.save();
      expect(cubit.state.problemsFor('pinnedAlternatives'), [
        'pinnedAlternatives has invalid id "ex_missing"',
      ]);
      expect(cubit.state.problemsFor('excludedAlternatives'), [
        'excludedAlternatives has invalid id "ex_dumbbell_press"',
      ]);
    });

    test('an unweighted logging type drops the increment', () async {
      final cubit = await open('ex_dumbbell_press');
      cubit.change((d) => d.copyWith(loggingType: LoggingType.reps));
      expect(cubit.state.draft.incrementKg, isNull);
      expect(cubit.state.draft.takesIncrement, isFalse);
    });
  });

  group('status', () {
    test('retire and publish write the new status', () async {
      final cubit = await open('ex_dumbbell_press');

      await cubit.saveAs(ExerciseStatus.retired);
      expect(cubit.state.loaded?.draft.status, ExerciseStatus.retired);
      expect(cubit.state.draft.status, ExerciseStatus.retired);

      await cubit.saveAs(ExerciseStatus.draft);
      expect(cubit.state.loaded?.draft.status, ExerciseStatus.draft);

      await cubit.saveAs(ExerciseStatus.live);
      expect(cubit.state.loaded?.draft.status, ExerciseStatus.live);
      verify(
        () => repository.update(
          any(),
          loadedUpdatedAt: any(named: 'loadedUpdatedAt'),
        ),
      ).called(3);
    });

    test('an invalid exercise is not published and keeps its status', () async {
      final cubit = await open('ex_dumbbell_press');
      await cubit.saveAs(ExerciseStatus.draft);
      cubit.change((d) => d.copyWith(cues: []));

      await cubit.saveAs(ExerciseStatus.live);

      expect(cubit.state.draft.status, ExerciseStatus.draft);
      expect(cubit.state.problemsFor('l10n.en.cues'), isNotEmpty);
      verify(
        () => repository.update(
          any(),
          loadedUpdatedAt: any(named: 'loadedUpdatedAt'),
        ),
      ).called(1);
    });
  });

  group('lost updates', () {
    test(
      'a document changed since loading is refused, then reloaded',
      () async {
        when(
          () => repository.update(
            any(),
            loadedUpdatedAt: any(named: 'loadedUpdatedAt'),
          ),
        ).thenAnswer((_) async => const Ok(ChangedSinceLoaded()));
        final cubit = await open('ex_dumbbell_press');
        cubit.change((d) => d.copyWith(popularity: 4));

        await cubit.save();
        expect(cubit.state.status, EditorStatus.changedSinceLoaded);
        // Editing on does not hide the refusal.
        cubit.change((d) => d.copyWith(popularity: 5));
        expect(cubit.state.status, EditorStatus.changedSinceLoaded);

        final newer = record(
          validJson()..['popularity'] = 7,
          updatedAt: DateTime.utc(2026, 11, 3),
        );
        when(() => repository.load('ex_dumbbell_press'))
            .thenAnswer((_) async => Ok(newer));
        final version = cubit.state.formVersion;
        await cubit.reload();

        expect(cubit.state.status, EditorStatus.editing);
        expect(cubit.state.draft, newer.draft);
        expect(cubit.state.loaded, newer);
        expect(cubit.state.formVersion, version + 1);
      },
    );
  });

  test('a denied write says the user may not edit', () async {
    when(
      () => repository.update(
        any(),
        loadedUpdatedAt: any(named: 'loadedUpdatedAt'),
      ),
    ).thenAnswer((_) async => const Err(PermissionFailure()));
    final cubit = await open('ex_dumbbell_press');

    await cubit.save();

    expect(cubit.state.status, EditorStatus.saveFailed);
    expect(cubit.state.failure, isA<PermissionFailure>());
    expect(
      failureMessage(cubit.state.failure!),
      startsWith('You are not allowed to edit'),
    );
  });
}
