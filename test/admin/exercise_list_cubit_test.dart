import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/exercises/domain/admin_exercise_repository.dart';
import 'package:get_workout/admin/exercises/domain/exercise_admin_usecases.dart';
import 'package:get_workout/admin/exercises/domain/exercise_draft.dart';
import 'package:get_workout/admin/exercises/presentation/exercise_list_cubit.dart';
import 'package:get_workout/admin/programs/domain/admin_program_repository.dart';
import 'package:get_workout/admin/programs/domain/program_admin_usecases.dart';
import 'package:get_workout/admin/programs/domain/program_draft.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';
import 'program_fixtures.dart';

class MockRepository extends Mock implements AdminExerciseRepository {}

class MockProgramRepository extends Mock implements AdminProgramRepository {}

void main() {
  late MockRepository repository;
  late MockProgramRepository programRepository;
  late StreamController<List<ExerciseRecord>> records;
  late StreamController<List<ProgramRecord>> programs;
  late ExerciseListCubit cubit;

  final press = record(validJson(id: 'ex_press', name: 'Press'));
  final curl = record(
    validJson(id: 'ex_curl', name: 'Curl', popularity: 2, family: 'curl')
      ..['mainMuscles'] = ['biceps']
      ..['secondaryMuscles'] = ['forearm']
      ..['equipment'] = ['cable']
      ..['equipmentAlternatives'] = [
        ['resistance_band'],
      ],
  );
  final row = record(
    validJson(
      id: 'ex_row',
      name: 'Row',
      popularity: 3,
      status: 'draft',
      family: 'row',
    ),
  );
  final dip = record(
    validJson(
        id: 'ex_dip',
        name: 'Dip',
        popularity: 9,
        status: 'retired',
        family: 'dip',
      )
      ..['l10n'] = {
        'en': {
          ...(validJson()['l10n']! as Map)['en'] as Map<String, Object?>,
          'name': 'Dip',
          'aliases': ['Parallel Bar Dip'],
        },
      },
  );

  setUp(() async {
    repository = MockRepository();
    programRepository = MockProgramRepository();
    records = StreamController();
    programs = StreamController();
    when(() => repository.watchAll()).thenAnswer((_) => records.stream);
    when(() => programRepository.watchAll()).thenAnswer((_) => programs.stream);
    // No retry fires during a test: the streams can be listened to only
    // once.
    cubit = ExerciseListCubit(
      watchExerciseRecords: WatchExerciseRecords(repository),
      watchPrograms: WatchPrograms(programRepository),
      firstRetryDelay: const Duration(hours: 1),
    );
    records.add([dip, row, curl, press]);
    await pumpEventQueue();
  });

  tearDown(() => cubit.close());

  List<String> visible() => [for (final r in cubit.state.visible) r.id];

  test('shows every status, by popularity, with counts per status', () {
    expect(visible(), ['ex_press', 'ex_curl', 'ex_row', 'ex_dip']);
    expect(cubit.state.counts, {
      ExerciseStatus.draft: 1,
      ExerciseStatus.live: 2,
      ExerciseStatus.retired: 1,
    });
  });

  test('sorts by a column, flipping on a second tap', () {
    cubit.sortBy(ExerciseColumn.name);
    expect(visible(), ['ex_curl', 'ex_dip', 'ex_press', 'ex_row']);
    expect(cubit.state.ascending, isTrue);

    cubit.sortBy(ExerciseColumn.name);
    expect(visible(), ['ex_row', 'ex_press', 'ex_dip', 'ex_curl']);
    expect(cubit.state.ascending, isFalse);

    // Another column starts ascending.
    cubit.sortBy(ExerciseColumn.family);
    expect(cubit.state.ascending, isTrue);
    expect(visible(), ['ex_curl', 'ex_dip', 'ex_press', 'ex_row']);
  });

  test('sorts numbers with blanks last either way', () async {
    final unranked = record(
      validJson(id: 'ex_unranked', name: 'Unranked')..remove('popularity'),
    );
    records.add([unranked, row, curl, press]);
    await pumpEventQueue();

    cubit.sortBy(ExerciseColumn.popularity);
    expect(visible(), ['ex_press', 'ex_curl', 'ex_row', 'ex_unranked']);
    cubit.sortBy(ExerciseColumn.popularity);
    expect(visible(), ['ex_row', 'ex_curl', 'ex_press', 'ex_unranked']);
  });

  test('sorts codes by label, lists by their first, ties by popularity', () {
    // Draft, Live, Live, Retired; the two live ones by popularity.
    cubit.sortBy(ExerciseColumn.status);
    expect(visible(), ['ex_row', 'ex_press', 'ex_curl', 'ex_dip']);

    // Biceps before pec; the three pressing ones by popularity.
    cubit.sortBy(ExerciseColumn.mainMuscles);
    expect(visible(), ['ex_curl', 'ex_press', 'ex_row', 'ex_dip']);
  });

  test('sorts dates by time', () async {
    final older = record(
      validJson(id: 'ex_old', name: 'Old', popularity: 2, family: 'old'),
      updatedAt: DateTime.utc(2025),
    );
    records.add([press, older]);
    await pumpEventQueue();
    cubit.sortBy(ExerciseColumn.updated);
    expect(visible(), ['ex_old', 'ex_press']);
  });

  test('searches name, alias and id', () {
    cubit.search('PRESS');
    expect(visible(), ['ex_press']);
    cubit.search('parallel');
    expect(visible(), ['ex_dip']);
    cubit.search('ex_ro');
    expect(visible(), ['ex_row']);
  });

  test('filters by every code, family, and combines filters', () async {
    final squat = record(
      validJson(id: 'ex_squat', name: 'Squat', popularity: 4, family: 'squat')
        ..['level'] = 'advanced'
        ..['mechanic'] = 'isolation'
        ..['movementPattern'] = 'squat'
        ..['loggingType'] = 'reps',
    );
    records.add([squat, curl, press]);
    await pumpEventQueue();

    cubit.filterLevel(Level.advanced);
    expect(visible(), ['ex_squat']);
    cubit.filterLevel(null);
    cubit.filterMechanic(Mechanic.isolation);
    expect(visible(), ['ex_squat']);
    cubit.filterMechanic(null);
    cubit.filterMovementPattern(MovementPattern.squat);
    expect(visible(), ['ex_squat']);
    cubit.filterMovementPattern(null);
    cubit.filterLoggingType(LoggingType.reps);
    expect(visible(), ['ex_squat']);
    cubit.filterLoggingType(null);
    cubit.filterSecondaryMuscle(Muscle.forearm);
    expect(visible(), ['ex_curl']);
    cubit.filterSecondaryMuscle(null);
    expect(cubit.state.families, ['curl', 'dumbbell_press', 'squat']);
    cubit.filterFamily('curl');
    expect(visible(), ['ex_curl']);

    // Filters combine.
    cubit.filterLevel(Level.advanced);
    expect(visible(), isEmpty);
    expect(cubit.state.hasFilters, isTrue);

    cubit
      ..search('pr')
      ..sortBy(ExerciseColumn.name)
      ..clearFilters();
    expect(cubit.state.hasFilters, isFalse);
    // The search and the sort stay.
    expect(visible(), ['ex_press']);
    expect(cubit.state.sortColumn, ExerciseColumn.name);
  });

  test(
    'problems only: health findings and exercises no program uses',
    () async {
      final broken = record(
        validJson(id: 'ex_gap', name: 'Gap', popularity: 3, family: 'gap')
          ..['secondaryMuscles'] = ['pec'],
      );
      final sameName = record(
        validJson(
          id: 'ex_curl_copy',
          name: 'curl',
          popularity: 4,
          family: 'cc',
        ),
      );
      final used = record(validJson(popularity: 5, family: 'db_press'));
      records.add([press, curl, broken, sameName, row, dip, used]);
      await pumpEventQueue();
      cubit.showUnusedOnly(true);
      // Until the programs arrive, nothing counts as unused.
      expect(visible(), isEmpty);
      cubit
        ..showUnusedOnly(false)
        ..showProblemsOnly(true);
      // An invalid document and both exercises a name clash names.
      expect(visible(), ['ex_curl', 'ex_gap', 'ex_curl_copy']);

      // A program uses ex_dumbbell_press and the curl. ex_press and the
      // row (a draft) are used by none; a retired exercise never counts as
      // unused. Being unused is not a problem.
      programs.add([programRecord(programJson())]);
      await pumpEventQueue();
      expect(visible(), ['ex_curl', 'ex_gap', 'ex_curl_copy']);
      expect(cubit.state.problemCount, 3);

      cubit
        ..showProblemsOnly(false)
        ..showUnusedOnly(true);
      expect(visible(), ['ex_press', 'ex_gap', 'ex_row', 'ex_curl_copy']);
      expect(cubit.state.unusedCount, 4);

      // The switches combine, and Clear filters resets both.
      cubit.showProblemsOnly(true);
      expect(visible(), ['ex_gap', 'ex_curl_copy']);
      cubit.clearFilters();
      expect(cubit.state.problemsOnly, isFalse);
      expect(cubit.state.unusedOnly, isFalse);
    },
  );

  test('problems only: live members of a family a finding is about', () async {
    // Two live curls both rank 1.
    final second = record(
      validJson(id: 'ex_curl_two', name: 'Curl Two', popularity: 3)
        ..['family'] = 'curl',
    );
    records.add([press, curl, second]);
    programs.add([]);
    await pumpEventQueue();
    expect(
      cubit.state.health!.errors,
      contains(startsWith('family curl has repeated ranks')),
    );
    cubit.showProblemsOnly(true);
    expect(visible(), ['ex_curl', 'ex_curl_two']);
  });

  group('generator tier', () {
    ExerciseRecord rated(String name, int popularity, String tier) => record(
      validJson(
        id: 'ex_${name.toLowerCase()}',
        name: name,
        popularity: popularity,
        family: name.toLowerCase(),
      )..['generatorTier'] = tier,
    );

    // The press has no tier; the others one each.
    setUp(() async {
      records.add([
        rated('Dip', 9, 'never'),
        rated('Row', 3, 'fallback'),
        rated('Curl', 2, 'staple'),
        press,
        rated('Fly', 5, 'standard'),
      ]);
      await pumpEventQueue();
    });

    test('filters by each tier and by not rated', () {
      final expected = {
        GeneratorTier.staple: ['ex_curl'],
        GeneratorTier.standard: ['ex_fly'],
        GeneratorTier.fallback: ['ex_row'],
        GeneratorTier.never: ['ex_dip'],
      };
      for (final MapEntry(key: tier, value: ids) in expected.entries) {
        cubit.filterGeneratorTier((tier: tier));
        expect(visible(), ids, reason: tier.code);
      }
      cubit.filterGeneratorTier((tier: null));
      expect(visible(), ['ex_press']);
      expect(cubit.state.hasFilters, isTrue);

      // It combines with the other filters, and Clear filters resets it.
      cubit.filterStatus(ExerciseStatus.retired);
      expect(visible(), isEmpty);
      cubit.clearFilters();
      expect(cubit.state.generatorTier, isNull);
      expect(visible(), hasLength(5));
    });

    test('sorts by the tier order, not rated last either way', () {
      cubit.sortBy(ExerciseColumn.generatorTier);
      expect(visible(), ['ex_curl', 'ex_fly', 'ex_row', 'ex_dip', 'ex_press']);
      cubit.sortBy(ExerciseColumn.generatorTier);
      expect(visible(), ['ex_dip', 'ex_row', 'ex_fly', 'ex_curl', 'ex_press']);
    });
  });

  test('a programs stream failure is kept apart', () async {
    programs.addError(const NetworkFailure());
    await pumpEventQueue();
    expect(cubit.state.programsFailure, isA<NetworkFailure>());
    expect(cubit.state.failure, isNull);
  });

  test('filters by status, main muscle and equipment', () {
    cubit.filterStatus(ExerciseStatus.draft);
    expect(visible(), ['ex_row']);
    cubit.filterStatus(null);

    cubit.filterMuscle(Muscle.biceps);
    expect(visible(), ['ex_curl']);
    // Forearm is only a secondary muscle of the curl.
    cubit.filterMuscle(Muscle.forearm);
    expect(visible(), isEmpty);
    cubit.filterMuscle(null);

    // An alternative set counts.
    cubit.filterEquipment(Equipment.resistanceBand);
    expect(visible(), ['ex_curl']);
  });

  test('keeps search and filters when the documents change', () async {
    cubit.filterStatus(ExerciseStatus.live);
    records.add([press]);
    await pumpEventQueue();
    expect(visible(), ['ex_press']);
    expect(cubit.state.status, ExerciseStatus.live);
  });

  test('summarizes library health from the loaded documents', () async {
    final health = cubit.state.health!;
    // Live popularity is 1, 2: complete. Ranks are complete per family.
    expect(health.errors.where((e) => !e.startsWith('coverage:')), isEmpty);
    expect(health.errors, contains('coverage: total has 2, needs 400'));
    expect(health.invalidIds, isEmpty);

    final broken = record(
      validJson(id: 'ex_gap', name: 'Gap', popularity: 5, family: 'gap')
        ..['secondaryMuscles'] = ['pec'],
    );
    records.add([press, curl, broken]);
    await pumpEventQueue();
    expect(cubit.state.health!.errors, contains('popularity 3 is unused'));
    expect(cubit.state.health!.invalidIds, ['ex_gap']);
  });

  test('a stream failure keeps the last list', () async {
    records.addError(const PermissionFailure());
    await pumpEventQueue();
    expect(cubit.state.failure, isA<PermissionFailure>());
    expect(cubit.state.records, hasLength(4));
  });

  group('after a stream error', () {
    late List<StreamController<List<ExerciseRecord>>> streams;

    setUp(() {
      streams = [];
      when(() => repository.watchAll()).thenAnswer((_) {
        final stream = StreamController<List<ExerciseRecord>>();
        streams.add(stream);
        return stream.stream;
      });
      when(() => programRepository.watchAll())
          .thenAnswer((_) => const Stream.empty());
    });

    test('listens again, waiting longer after each failure in a row', () {
      fakeAsync((async) {
        final cubit = ExerciseListCubit(
          watchExerciseRecords: WatchExerciseRecords(repository),
          watchPrograms: WatchPrograms(programRepository),
        );
        async.flushMicrotasks();
        streams.last.addError(const NetworkFailure());
        async.flushMicrotasks();
        expect(cubit.state.failure, isA<NetworkFailure>());

        async.elapse(const Duration(milliseconds: 999));
        expect(streams, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(streams, hasLength(2));

        // A second failure in a row waits twice as long.
        streams.last.addError(const NetworkFailure());
        async.elapse(const Duration(milliseconds: 1999));
        expect(streams, hasLength(2));
        async.elapse(const Duration(milliseconds: 1));
        expect(streams, hasLength(3));

        // Data clears the failure and the backoff.
        streams.last.add([press]);
        async.flushMicrotasks();
        expect(cubit.state.failure, isNull);
        expect(cubit.state.records, [press]);
        streams.last.addError(const NetworkFailure());
        async.elapse(const Duration(seconds: 1));
        expect(streams, hasLength(4));

        cubit.close();
        async.flushMicrotasks();
      });
    });

    test('retry listens again at once', () {
      fakeAsync((async) {
        final cubit = ExerciseListCubit(
          watchExerciseRecords: WatchExerciseRecords(repository),
          watchPrograms: WatchPrograms(programRepository),
        );
        async.flushMicrotasks();
        streams.last.addError(const NetworkFailure());
        async.flushMicrotasks();

        cubit.retry();
        expect(streams, hasLength(2));
        // The scheduled retry was replaced.
        async.elapse(const Duration(seconds: 5));
        expect(streams, hasLength(2));

        cubit.close();
        async.flushMicrotasks();
      });
    });
  });
}
