import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/exercises/presentation/favorites_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockUserLibraryRepository extends Mock implements UserLibraryRepository {}

void main() {
  const guest = AuthUser(id: 'g1', isAnonymous: true);
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  const failure = NetworkFailure();
  const retryDelay = Duration(milliseconds: 20);

  late MockAuthRepository auth;
  late MockUserLibraryRepository library;
  late StreamController<AuthUser?> users;

  /// Every subscription to a user's favourites, oldest first.
  late Map<String, List<StreamController<Set<String>>>> watched;

  StreamController<Set<String>> latest(String uid) => watched[uid]!.last;

  setUp(() {
    auth = MockAuthRepository();
    library = MockUserLibraryRepository();
    users = StreamController<AuthUser?>();
    watched = {};
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => library.watchFavorites(any())).thenAnswer((call) {
      final controller = StreamController<Set<String>>();
      watched
          .putIfAbsent(call.positionalArguments.first as String, () => [])
          .add(controller);
      return controller.stream;
    });
  });

  FavoritesCubit build({Duration delay = retryDelay}) => FavoritesCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchFavorites: WatchFavorites(library),
    setFavorite: SetFavorite(library),
    retryDelay: delay,
  );

  void writesReturn(Future<Result<void>> Function() result) => when(
    () => library.setFavorite(any(), any(), favorite: any(named: 'favorite')),
  ).thenAnswer((_) => result());

  Future<void> signIn(AuthUser user, Set<String> favorites) async {
    users.add(user);
    await pumpEventQueue();
    latest(user.id).add(favorites);
    await pumpEventQueue();
  }

  test('starts empty', () {
    expect(build().state, const FavoritesState({}));
  });

  blocTest<FavoritesCubit, FavoritesState>(
    'follows whoever is signed in and resets at once on a user change',
    build: build,
    act: (_) async {
      await signIn(guest, {'squat'});
      users.add(member);
      await pumpEventQueue();
      latest('u1').add({'bench'});
      await pumpEventQueue();
      // The previous user's stream is no longer followed.
      latest('g1').add({'deadlift'});
    },
    expect: () => [
      const FavoritesState({'squat'}),
      const FavoritesState({}),
      const FavoritesState({'bench'}),
    ],
    verify: (_) => expect(latest('g1').hasListener, isFalse),
  );

  blocTest<FavoritesCubit, FavoritesState>(
    'signing out empties them',
    build: build,
    act: (_) async {
      await signIn(member, {'squat'});
      users.add(null);
    },
    expect: () => [
      const FavoritesState({'squat'}),
      const FavoritesState({}),
    ],
  );

  blocTest<FavoritesCubit, FavoritesState>(
    'toggle adds a missing one and removes a present one, for the current user',
    setUp: () => writesReturn(() async => const Ok(null)),
    build: build,
    act: (cubit) async {
      await signIn(member, {'squat'});
      await cubit.toggle('bench');
      await cubit.toggle('squat');
    },
    expect: () => [
      const FavoritesState({'squat'}),
    ],
    verify: (_) {
      verify(() => library.setFavorite('u1', 'bench', favorite: true))
          .called(1);
      verify(() => library.setFavorite('u1', 'squat', favorite: false))
          .called(1);
    },
  );

  blocTest<FavoritesCubit, FavoritesState>(
    'a failed toggle keeps the favourites and reports the failure',
    setUp: () => writesReturn(() async => const Err(failure)),
    build: build,
    act: (cubit) async {
      await signIn(member, {'squat'});
      await cubit.toggle('bench');
    },
    expect: () => [
      const FavoritesState({'squat'}),
      const FavoritesState({'squat'}, failure: failure),
    ],
  );

  blocTest<FavoritesCubit, FavoritesState>(
    'a failed stream is followed again after a backoff',
    build: build,
    act: (_) async {
      await signIn(member, {'squat'});
      latest('u1').addError(const PermissionFailure());
      await pumpEventQueue();
      expect(watched['u1'], hasLength(1));

      await Future<void>.delayed(retryDelay * 2);
      expect(watched['u1'], hasLength(2));
      latest('u1').add({'squat', 'bench'});
    },
    expect: () => [
      const FavoritesState({'squat'}),
      const FavoritesState({'squat', 'bench'}),
    ],
  );

  blocTest<FavoritesCubit, FavoritesState>(
    'a stream that keeps failing waits longer each time',
    build: build,
    act: (_) async {
      await signIn(member, {'squat'});
      latest('u1').addError(const PermissionFailure());
      await Future<void>.delayed(retryDelay * 1.5);
      expect(watched['u1'], hasLength(2));

      latest('u1').addError(const PermissionFailure());
      await Future<void>.delayed(retryDelay * 1.5);
      // The second retry waits twice as long.
      expect(watched['u1'], hasLength(2));
      await Future<void>.delayed(retryDelay * 1.5);
      expect(watched['u1'], hasLength(3));
    },
    expect: () => [
      const FavoritesState({'squat'}),
    ],
  );

  blocTest<FavoritesCubit, FavoritesState>(
    'a tap while the stream is down writes from the last known favourites '
    'and follows the stream again at once',
    setUp: () => writesReturn(() async => const Ok(null)),
    build: () => build(delay: const Duration(hours: 1)),
    act: (cubit) async {
      await signIn(member, {'squat'});
      latest('u1').addError(const NetworkFailure());
      await pumpEventQueue();

      await cubit.toggle('squat');
      expect(watched['u1'], hasLength(2));
      latest('u1').add({});
    },
    expect: () => [
      const FavoritesState({'squat'}),
      const FavoritesState({}),
    ],
    verify: (_) =>
        verify(() => library.setFavorite('u1', 'squat', favorite: false))
            .called(1),
  );

  final write = Completer<Result<void>>();
  blocTest<FavoritesCubit, FavoritesState>(
    "a write's outcome is ignored once another user is signed in",
    setUp: () => writesReturn(() => write.future),
    build: build,
    act: (cubit) async {
      await signIn(guest, {'squat'});
      final toggled = cubit.toggle('bench');
      await signIn(member, {'row'});
      write.complete(const Err(failure));
      await toggled;
    },
    expect: () => [
      const FavoritesState({'squat'}),
      const FavoritesState({}),
      const FavoritesState({'row'}),
    ],
  );

  blocTest<FavoritesCubit, FavoritesState>(
    'toggle without a user writes nothing',
    build: build,
    act: (cubit) => cubit.toggle('squat'),
    expect: () => const <FavoritesState>[],
    verify: (_) => verifyNever(
      () => library.setFavorite(any(), any(), favorite: any(named: 'favorite')),
    ),
  );
}
