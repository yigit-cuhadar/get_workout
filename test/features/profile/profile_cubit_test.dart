import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

void main() {
  const guest = AuthUser(id: 'g1', isAnonymous: true);
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  const strong = UserProfile(goal: Goal.getStronger);
  const lean = UserProfile(goal: Goal.loseFat);

  late MockAuthRepository auth;
  late MockProfileRepository profiles;
  late StreamController<AuthUser?> users;
  late Map<String, StreamController<UserProfile>> stored;

  setUp(() {
    auth = MockAuthRepository();
    profiles = MockProfileRepository();
    users = StreamController<AuthUser?>();
    stored = {};
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => profiles.watchProfile(any())).thenAnswer(
      (call) => stored
          .putIfAbsent(
            call.positionalArguments.first as String,
            StreamController<UserProfile>.new,
          )
          .stream,
    );
  });

  ProfileCubit build() => ProfileCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchProfile: WatchProfile(profiles),
  );

  ProfileState loaded(String uid, UserProfile profile) =>
      ProfileState(uid: uid, status: ProfileStatus.loaded, profile: profile);

  test('starts loading, for nobody', () {
    expect(build().state, const ProfileState());
  });

  blocTest<ProfileCubit, ProfileState>(
    'follows the profile of whoever is signed in',
    build: build,
    act: (_) async {
      users.add(guest);
      await pumpEventQueue();
      stored['g1']!.add(strong);
      await pumpEventQueue();
      stored['g1']!.add(lean);
      await pumpEventQueue();
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add(strong);
      await pumpEventQueue();
      // The previous user's stream is no longer followed.
      stored['g1']!.add(const UserProfile());
    },
    expect: () => [
      const ProfileState(uid: 'g1'),
      loaded('g1', strong),
      loaded('g1', lean),
      const ProfileState(uid: 'u1'),
      loaded('u1', strong),
    ],
    verify: (_) => expect(stored['g1']!.hasListener, isFalse),
  );

  blocTest<ProfileCubit, ProfileState>(
    "a user change resets at once, never showing the previous user's answers",
    build: build,
    act: (cubit) async {
      users.add(guest);
      await pumpEventQueue();
      stored['g1']!.add(strong);
      await pumpEventQueue();
      users.add(member);
      await pumpEventQueue();
      expect(cubit.state, const ProfileState(uid: 'u1'));
    },
    expect: () => [
      const ProfileState(uid: 'g1'),
      loaded('g1', strong),
      const ProfileState(uid: 'u1'),
    ],
  );

  blocTest<ProfileCubit, ProfileState>(
    'signing out empties the profile',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add(strong);
      await pumpEventQueue();
      users.add(null);
    },
    expect: () => [
      const ProfileState(uid: 'u1'),
      loaded('u1', strong),
      const ProfileState(),
    ],
  );

  blocTest<ProfileCubit, ProfileState>(
    'linking the guest (same uid) keeps the subscription and the profile',
    build: build,
    act: (_) async {
      users.add(guest);
      await pumpEventQueue();
      stored['g1']!.add(strong);
      await pumpEventQueue();
      users.add(const AuthUser(id: 'g1', email: 'a@b.co'));
    },
    expect: () => [const ProfileState(uid: 'g1'), loaded('g1', strong)],
    verify: (_) => verify(() => profiles.watchProfile('g1')).called(1),
  );

  blocTest<ProfileCubit, ProfileState>(
    'a profile that cannot be loaded is unavailable',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.addError(const NetworkFailure());
    },
    expect: () => [
      const ProfileState(uid: 'u1'),
      const ProfileState(uid: 'u1', status: ProfileStatus.unavailable),
    ],
  );

  blocTest<ProfileCubit, ProfileState>(
    'a later stream error keeps the last profile',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!
        ..add(strong)
        ..addError(const PermissionFailure());
    },
    expect: () => [const ProfileState(uid: 'u1'), loaded('u1', strong)],
  );
}
