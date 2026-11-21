import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/exercises/domain/admin_exercise_repository.dart';
import 'package:get_workout/admin/exercises/domain/exercise_admin_usecases.dart';
import 'package:get_workout/admin/exercises/domain/exercise_draft.dart';
import 'package:get_workout/admin/programs/domain/admin_program_repository.dart';
import 'package:get_workout/admin/programs/domain/program_admin_usecases.dart';
import 'package:get_workout/admin/programs/domain/program_draft.dart';
import 'package:get_workout/admin/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/catalogue_rules.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';
import 'program_fixtures.dart';

class MockRepository extends Mock implements AdminProgramRepository {}

class MockExerciseRepository extends Mock implements AdminExerciseRepository {}

void main() {
  late MockRepository repository;
  late MockExerciseRepository exerciseRepository;
  late StreamController<List<ProgramRecord>> cards;
  late StreamController<List<ExerciseRecord>> library;
  late ProgramListCubit cubit;

  ProgramRecord card(Map<String, Object?> json) => programRecord(json);

  final basics = card(programJson());
  final strength = card(
    programJson(id: 'pr_strength', name: 'Strength', order: 2, premium: true),
  );
  final draft = card(
    programJson(id: 'pr_new', name: 'New', order: 3, status: 'draft'),
  );
  final unordered = card(
    programJson(id: 'pr_a_unordered', name: 'Unordered')..remove('order'),
  );

  setUp(() async {
    repository = MockRepository();
    exerciseRepository = MockExerciseRepository();
    cards = StreamController();
    library = StreamController();
    when(() => repository.watchAll()).thenAnswer((_) => cards.stream);
    when(() => exerciseRepository.watchAll()).thenAnswer((_) => library.stream);
    // No retry fires during a test: the streams can be listened to only
    // once.
    cubit = ProgramListCubit(
      watchPrograms: WatchPrograms(repository),
      watchExerciseRecords: WatchExerciseRecords(exerciseRepository),
      firstRetryDelay: const Duration(hours: 1),
    );
    cards.add([unordered, draft, strength, basics]);
    await pumpEventQueue();
  });

  tearDown(() => cubit.close());

  List<String> visible() => [for (final r in cubit.state.visible) r.id];

  test('shows every status by order, unordered last, with counts', () {
    expect(visible(), [
      'pr_dumbbell_basics',
      'pr_strength',
      'pr_new',
      'pr_a_unordered',
    ]);
    expect(cubit.state.counts, {
      ExerciseStatus.draft: 1,
      ExerciseStatus.live: 3,
      ExerciseStatus.retired: 0,
    });
  });

  test('searches name and id, and filters by status', () {
    cubit.search('STRENGTH');
    expect(visible(), ['pr_strength']);
    cubit.search('pr_new');
    expect(visible(), ['pr_new']);
    cubit.search('');
    cubit.filterStatus(ExerciseStatus.draft);
    expect(visible(), ['pr_new']);
  });

  test('sorts by a column, flipping on a second tap, blanks last', () {
    cubit.sortBy(ProgramColumn.order);
    expect(visible(), [
      'pr_dumbbell_basics',
      'pr_strength',
      'pr_new',
      'pr_a_unordered',
    ]);
    cubit.sortBy(ProgramColumn.order);
    expect(cubit.state.ascending, isFalse);
    expect(visible(), [
      'pr_new',
      'pr_strength',
      'pr_dumbbell_basics',
      'pr_a_unordered',
    ]);

    // Free before premium; ties keep the catalogue order.
    cubit.sortBy(ProgramColumn.access);
    expect(cubit.state.ascending, isTrue);
    expect(visible(), [
      'pr_dumbbell_basics',
      'pr_new',
      'pr_a_unordered',
      'pr_strength',
    ]);

    cubit.sortBy(ProgramColumn.name);
    expect(visible(), [
      'pr_dumbbell_basics',
      'pr_new',
      'pr_strength',
      'pr_a_unordered',
    ]);
  });

  test('sorts dates by time and codes by label', () async {
    cards.add([
      programRecord(
        programJson(id: 'pr_late', name: 'Late', order: 2)
          ..['level'] = 'advanced',
        card: DateTime.utc(2026, 5),
      ),
      programRecord(programJson(), card: DateTime.utc(2026, 1)),
    ]);
    await pumpEventQueue();
    cubit.sortBy(ProgramColumn.updated);
    cubit.sortBy(ProgramColumn.updated);
    expect(visible(), ['pr_late', 'pr_dumbbell_basics']);
    // Advanced before Beginner.
    cubit.sortBy(ProgramColumn.level);
    expect(visible(), ['pr_late', 'pr_dumbbell_basics']);
  });

  test('filters by access, level, goal, days and equipment profile', () {
    cubit.filterAccess(true);
    expect(visible(), ['pr_strength']);
    cubit.filterAccess(false);
    expect(visible(), ['pr_dumbbell_basics', 'pr_new', 'pr_a_unordered']);
    expect(cubit.state.accessCounts, {false: 3, true: 1});
    cubit.filterAccess(null);

    cubit.filterLevel(Level.advanced);
    expect(visible(), isEmpty);
    cubit.filterLevel(Level.beginner);
    expect(visible(), hasLength(4));
    cubit.filterGoal(Goal.buildMuscle);
    expect(visible(), hasLength(4));
    cubit.filterEquipmentProfile(EquipmentProfile.dumbbells);
    expect(visible(), hasLength(4));
    expect(cubit.state.daysPerWeekValues, [2]);
    cubit.filterDaysPerWeek(3);
    expect(visible(), isEmpty);
    expect(cubit.state.hasFilters, isTrue);

    cubit
      ..search('strength')
      ..clearFilters();
    expect(cubit.state.hasFilters, isFalse);
    expect(visible(), ['pr_strength']);
  });

  test(
    'problems only: catalogue rule problems and weekly-set warnings',
    () async {
      // One exercise per major muscle; six sets of each is inside the
      // beginner band, so this program gets no warning.
      final moves = [
        for (final (index, muscle) in majorMuscles.indexed)
          record(
            validJson(
                id: 'ex_m${index}_${muscle.code}',
                name: 'Move ${muscle.code}',
                popularity: index + 1,
                family: 'm${index}_${muscle.code}',
              )
              ..['mainMuscles'] = [muscle.code]
              ..['secondaryMuscles'] = <String>[],
          ),
      ];
      final balanced = programRecord(
        programJson(id: 'pr_balanced', name: 'Balanced', order: 4)
          ..['days'] = [
            {
              'name': 'Day A',
              'items': [
                for (final exercise in moves)
                  {
                    'exerciseId': exercise.id,
                    'sets': 6,
                    'repMin': 8,
                    'repMax': 12,
                    'restS': 60,
                  },
              ],
            },
          ],
      );
      final clash = programRecord(
        programJson(id: 'pr_clash', name: 'Balanced', order: 5)
          ..['days'] = balanced.json['days'],
      );
      cards.add([balanced]);
      library.add(moves);
      await pumpEventQueue();
      cubit.showProblemsOnly(true);
      expect(visible(), isEmpty);

      // A name clash is a problem of both programs, as each editor shows.
      cards.add([balanced, clash]);
      await pumpEventQueue();
      expect(visible(), ['pr_balanced', 'pr_clash']);
      expect(cubit.state.problemIds, {'pr_balanced', 'pr_clash'});

      // Basics gets a warning: no quads, back or hamstring work.
      cards.add([balanced, basics]);
      await pumpEventQueue();
      expect(visible(), ['pr_dumbbell_basics']);
    },
  );

  test('summarizes the catalogue health of the cards', () async {
    expect(cubit.state.health!.errors, [
      'live programs: 2 free and 1 premium, needs 6 and 23',
    ]);
    expect(cubit.state.health!.liveFree, 2);
    expect(cubit.state.health!.livePremium, 1);
    cards.add([basics, card(programJson(id: 'pr_copy', name: 'basics copy'))]);
    await pumpEventQueue();
    expect(
      cubit.state.health!.errors,
      contains('pr_copy: order "1" also used by pr_dumbbell_basics'),
    );
  });

  test('a stream failure keeps the last list', () async {
    cards.addError(const PermissionFailure());
    await pumpEventQueue();
    expect(cubit.state.failure, isA<PermissionFailure>());
    expect(cubit.state.records, hasLength(4));
  });

  test('after a stream error it listens again, then on retry at once', () {
    final streams = <StreamController<List<ProgramRecord>>>[];
    when(() => repository.watchAll()).thenAnswer((_) {
      final stream = StreamController<List<ProgramRecord>>();
      streams.add(stream);
      return stream.stream;
    });
    when(() => exerciseRepository.watchAll())
        .thenAnswer((_) => const Stream.empty());
    fakeAsync((async) {
      final cubit = ProgramListCubit(
        watchPrograms: WatchPrograms(repository),
        watchExerciseRecords: WatchExerciseRecords(exerciseRepository),
      );
      async.flushMicrotasks();
      streams.last.addError(const NetworkFailure());
      async.elapse(const Duration(milliseconds: 999));
      expect(streams, hasLength(1));
      async.elapse(const Duration(milliseconds: 1));
      expect(streams, hasLength(2));

      streams.last.addError(const NetworkFailure());
      async.flushMicrotasks();
      cubit.retry();
      expect(streams, hasLength(3));
      streams.last.add([basics]);
      async.flushMicrotasks();
      expect(cubit.state.failure, isNull);
      expect(cubit.state.records, [basics]);

      cubit.close();
      async.flushMicrotasks();
    });
  });
}
