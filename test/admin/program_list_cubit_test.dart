import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/programs/domain/admin_program_repository.dart';
import 'package:get_workout/admin/programs/domain/program_admin_usecases.dart';
import 'package:get_workout/admin/programs/domain/program_draft.dart';
import 'package:get_workout/admin/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:mocktail/mocktail.dart';

import 'program_fixtures.dart';

class MockRepository extends Mock implements AdminProgramRepository {}

void main() {
  late MockRepository repository;
  late StreamController<List<ProgramRecord>> cards;
  late ProgramListCubit cubit;

  ProgramRecord card(Map<String, Object?> json) => programRecord(cardOf(json));

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
    cards = StreamController();
    when(() => repository.watchCards()).thenAnswer((_) => cards.stream);
    // No retry fires during a test: [cards] can be listened to only once.
    cubit = ProgramListCubit(
      watchProgramCards: WatchProgramCards(repository),
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

  test('summarizes the catalogue health of the cards', () async {
    expect(cubit.state.health!.errors, [
      'live programs: 2 free and 1 premium, needs 6 and 19',
    ]);
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
    when(() => repository.watchCards()).thenAnswer((_) {
      final stream = StreamController<List<ProgramRecord>>();
      streams.add(stream);
      return stream.stream;
    });
    fakeAsync((async) {
      final cubit = ProgramListCubit(
        watchProgramCards: WatchProgramCards(repository),
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
