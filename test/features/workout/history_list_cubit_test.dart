import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/workout/domain/history_usecases.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/presentation/history_list_cubit.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

void main() {
  const alice = AuthUser(id: 'u1', isAnonymous: true);
  const bob = AuthUser(id: 'u2', isAnonymous: true);
  const c1 = HistoryCursor('c1');
  const c2 = HistoryCursor('c2');

  late StreamController<AuthUser?> users;
  late StreamController<Failure> rejected;
  late MockWorkoutRepository repository;

  /// The page streams asked for, by user, start and end.
  late Map<String, StreamController<HistoryPage>> pages;

  String key(String uid, HistoryCursor? after, HistoryCursor? through) =>
      '$uid ${after?.position} ${through?.position}';

  Workout w(String id) => workout(id, const []);

  HistoryPage page(List<String> ids, {HistoryCursor? end, bool more = false}) =>
      (workouts: [for (final id in ids) w(id)], end: end, more: more);

  setUp(() {
    users = StreamController<AuthUser?>();
    rejected = StreamController<Failure>.broadcast();
    repository = MockWorkoutRepository();
    pages = {};
    when(
      () => repository.watchHistory(
        any(),
        after: any(named: 'after'),
        through: any(named: 'through'),
      ),
    ).thenAnswer(
      (call) => pages
          .putIfAbsent(
            key(
              call.positionalArguments.first as String,
              call.namedArguments[#after] as HistoryCursor?,
              call.namedArguments[#through] as HistoryCursor?,
            ),
            StreamController<HistoryPage>.broadcast,
          )
          .stream,
    );
    when(() => repository.rejectedEdits).thenAnswer((_) => rejected.stream);
  });

  tearDown(() async {
    await users.close();
    await rejected.close();
  });

  Future<HistoryListCubit> signedIn([AuthUser user = alice]) async {
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    final cubit = HistoryListCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchHistory: WatchHistory(repository),
      watchRejectedEdits: WatchRejectedWorkoutEdits(repository),
    );
    users.add(user);
    await pumpEventQueue();
    return cubit;
  }

  Future<void> emit(String key, HistoryPage data) async {
    pages[key]!.add(data);
    await pumpEventQueue();
  }

  List<String> ids(HistoryListCubit cubit) => [
    for (final workout in cubit.state.workouts) workout.id,
  ];

  test('loads the first page', () async {
    final cubit = await signedIn();
    expect(cubit.state.status, HistoryListStatus.loading);
    await emit('u1 null null', page(['w3', 'w2'], end: c1, more: true));
    expect(cubit.state.status, HistoryListStatus.ready);
    expect(ids(cubit), ['w3', 'w2']);
    expect(cubit.state.more, isTrue);
    await cubit.close();
  });

  test('more pages follow, each earlier one given its end', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page(['w3', 'w2'], end: c1, more: true));

    cubit.loadMore();
    expect(cubit.state.loadingMore, isTrue);
    // So the list keeps a row for the spinner.
    expect(cubit.state.more, isTrue);
    expect(pages.keys, containsAll(['u1 null c1', 'u1 c1 null']));
    // Asking again while loading changes nothing.
    cubit.loadMore();
    expect(pages, hasLength(3));

    await emit('u1 c1 null', page(['w1'], end: c2));
    expect(ids(cubit), ['w3', 'w2', 'w1']);
    expect(cubit.state.loadingMore, isFalse);
    expect(cubit.state.more, isFalse);

    // The first page, now with an end, grows with a new workout.
    await emit('u1 null c1', page(['w4', 'w3', 'w2'], end: c1));
    expect(ids(cubit), ['w4', 'w3', 'w2', 'w1']);
    await cubit.close();
  });

  test('a workout moved between pages shows once', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page(['w3', 'w2'], end: c1, more: true));
    cubit.loadMore();
    await emit('u1 c1 null', page(['w2', 'w1']));
    expect(ids(cubit), ['w3', 'w2', 'w1']);
    await cubit.close();
  });

  test('pages past the live ones are read once', () async {
    final cubit = await signedIn();
    String? after;
    for (var i = 0; i <= HistoryListCubit.maxLivePages; i++) {
      final end = HistoryCursor('c$i');
      await emit('u1 $after null', page(['w$i'], end: end, more: true));
      after = 'c$i';
      cubit.loadMore();
    }
    // Page 6 (index 5) is the first read once: it stops after its answer.
    final once = pages['u1 c4 c5']!;
    expect(once.hasListener, isTrue);
    await emit('u1 c4 c5', page(['w5'], end: const HistoryCursor('c5')));
    expect(once.hasListener, isFalse);
    expect(pages['u1 c3 c4']!.hasListener, isTrue);
    expect(ids(cubit), ['w0', 'w1', 'w2', 'w3', 'w4', 'w5']);
    await cubit.close();
  });

  test('closing stops every listener', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page(['w1'], end: c1, more: true));
    cubit.loadMore();
    await cubit.close();
    expect(pages.values.any((c) => c.hasListener), isFalse);
  });

  test('without more nothing loads', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page(['w1'], end: c1));
    cubit.loadMore();
    expect(pages, hasLength(1));
    await cubit.close();
  });

  test('a failure is shown and retried', () async {
    final cubit = await signedIn();
    pages['u1 null null']!.addError(const NetworkFailure());
    await pumpEventQueue();
    expect(cubit.state.status, HistoryListStatus.failure);
    expect(cubit.state.failure, isA<NetworkFailure>());

    cubit.retry();
    expect(cubit.state.status, HistoryListStatus.loading);
    await emit('u1 null null', page(['w1']));
    expect(ids(cubit), ['w1']);
    await cubit.close();
  });

  test('another user starts over with their own', () async {
    final cubit = await signedIn();
    await emit('u1 null null', page(['w1']));
    users.add(bob);
    await pumpEventQueue();
    expect(cubit.state.status, HistoryListStatus.loading);
    expect(cubit.state.workouts, isEmpty);
    // The previous user's page no longer shows.
    pages['u1 null null']!.add(page(['w9']));
    await pumpEventQueue();
    expect(cubit.state.workouts, isEmpty);
    await emit('u2 null null', page(['w5']));
    expect(ids(cubit), ['w5']);
    await cubit.close();
  });

  test('a refused edit is reported once', () async {
    final cubit = await signedIn();
    rejected.add(const PermissionFailure());
    await pumpEventQueue();
    expect(cubit.state.writeRejected, isTrue);
    // It survives the list loading.
    await emit('u1 null null', page(['w1']));
    expect(cubit.state.writeRejected, isTrue);
    cubit.rejectionShown();
    expect(cubit.state.writeRejected, isFalse);
    await cubit.close();
  });
}
