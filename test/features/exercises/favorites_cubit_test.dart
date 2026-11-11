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

  late MockAuthRepository auth;
  late MockUserLibraryRepository library;
  late StreamController<AuthUser?> users;
  late Map<String, StreamController<Set<String>>> stored;

  setUp(() {
    auth = MockAuthRepository();
    library = MockUserLibraryRepository();
    users = StreamController<AuthUser?>();
    stored = {};
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => library.watchFavorites(any())).thenAnswer(
      (call) => stored
          .putIfAbsent(
            call.positionalArguments.first as String,
            StreamController<Set<String>>.new,
          )
          .stream,
    );
  });

  FavoritesCubit build() => FavoritesCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchFavorites: WatchFavorites(library),
    setFavorite: SetFavorite(library),
  );

  void writesReturn(Result<void> result) => when(
    () => library.setFavorite(any(), any(), favorite: any(named: 'favorite')),
  ).thenAnswer((_) async => result);

  test('starts empty', () {
    expect(build().state, const FavoritesState({}));
  });

  blocTest<FavoritesCubit, FavoritesState>(
    'follows whoever is signed in and resets at once on a user change',
    build: build,
    act: (_) async {
      users.add(guest);
      await pumpEventQueue();
      stored['g1']!.add({'squat'});
      await pumpEventQueue();
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add({'bench'});
      await pumpEventQueue();
      // The previous user's stream is no longer followed.
      stored['g1']!.add({'deadlift'});
    },
    expect: () => [
      const FavoritesState({'squat'}),
      const FavoritesState({}),
      const FavoritesState({'bench'}),
    ],
    verify: (_) => expect(stored['g1']!.hasListener, isFalse),
  );

  blocTest<FavoritesCubit, FavoritesState>(
    'signing out empties them',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add({'squat'});
      await pumpEventQueue();
      users.add(null);
    },
    expect: () => [
      const FavoritesState({'squat'}),
      const FavoritesState({}),
    ],
  );

  blocTest<FavoritesCubit, FavoritesState>(
    'toggle adds a missing one and removes a present one, for the current user',
    setUp: () => writesReturn(const Ok(null)),
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add({'squat'});
      await pumpEventQueue();
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
    setUp: () => writesReturn(const Err(failure)),
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add({'squat'});
      await pumpEventQueue();
      await cubit.toggle('bench');
    },
    expect: () => [
      const FavoritesState({'squat'}),
      const FavoritesState({'squat'}, failure: failure),
    ],
  );

  blocTest<FavoritesCubit, FavoritesState>(
    'a stream error keeps the last favourites',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!
        ..add({'squat'})
        ..addError(const PermissionFailure());
    },
    expect: () => [
      const FavoritesState({'squat'}),
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
