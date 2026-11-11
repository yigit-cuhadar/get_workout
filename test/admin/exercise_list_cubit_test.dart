import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/exercises/domain/admin_exercise_repository.dart';
import 'package:get_workout/admin/exercises/domain/exercise_admin_usecases.dart';
import 'package:get_workout/admin/exercises/domain/exercise_draft.dart';
import 'package:get_workout/admin/exercises/presentation/exercise_list_cubit.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockRepository extends Mock implements AdminExerciseRepository {}

void main() {
  late MockRepository repository;
  late StreamController<List<ExerciseRecord>> records;
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
    records = StreamController();
    when(() => repository.watchAll()).thenAnswer((_) => records.stream);
    cubit = ExerciseListCubit(
      watchExerciseRecords: WatchExerciseRecords(repository),
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

  test('sorts by name', () {
    cubit.sortBy(ExerciseSort.name);
    expect(visible(), ['ex_curl', 'ex_dip', 'ex_press', 'ex_row']);
  });

  test('searches name, alias and id', () {
    cubit.search('PRESS');
    expect(visible(), ['ex_press']);
    cubit.search('parallel');
    expect(visible(), ['ex_dip']);
    cubit.search('ex_ro');
    expect(visible(), ['ex_row']);
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
    });

    test('listens again, waiting longer after each failure in a row', () {
      fakeAsync((async) {
        final cubit = ExerciseListCubit(
          watchExerciseRecords: WatchExerciseRecords(repository),
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
