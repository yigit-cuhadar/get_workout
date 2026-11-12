import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

class MockUpdateProfile extends Mock implements UpdateProfile {}

void main() {
  const guest = AuthUser(id: 'g1', isAnonymous: true);
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  const strong = UserProfile(goal: Goal.getStronger);
  const lean = UserProfile(goal: Goal.loseFat);

  late MockAuthRepository auth;
  late MockProfileRepository profiles;
  late MockUpdateProfile updateProfile;
  late StreamController<AuthUser?> users;
  late Map<String, StreamController<UserProfile>> stored;

  setUpAll(() {
    registerFallbackValue((
      uid: '',
      profile: const UserProfile(),
      fields: <ProfileField>{},
    ));
  });

  setUp(() {
    updateProfile = MockUpdateProfile();
    when(() => updateProfile(any())).thenAnswer((_) async => const Ok(null));
    auth = MockAuthRepository();
    profiles = MockProfileRepository();
    users = StreamController<AuthUser?>();
    stored = {};
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    // Each subscription gets a fresh stream, as a re-listen does in
    // Firestore; [stored] holds the latest one per user.
    when(() => profiles.watchProfile(any())).thenAnswer(
      (call) =>
          (stored[call.positionalArguments.first as String] =
                  StreamController<UserProfile>())
              .stream,
    );
  });

  const retryDelay = Duration(milliseconds: 10);

  ProfileCubit build() => ProfileCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchProfile: WatchProfile(profiles),
    updateProfile: updateProfile,
    retryDelay: retryDelay,
  );

  ProfileState loaded(String uid, UserProfile profile) =>
      ProfileState(uid: uid, status: ProfileStatus.loaded, profile: profile);

  /// Runs [act] against a new cubit on fake time, so retries wait exactly
  /// their delay however loaded the machine is; returns the states emitted.
  List<ProfileState> onFakeTime(void Function(FakeAsync async) act) {
    final states = <ProfileState>[];
    fakeAsync((async) {
      final cubit = build();
      final subscription = cubit.stream.listen(states.add);
      act(async);
      async.flushMicrotasks();
      unawaited(subscription.cancel());
      unawaited(cubit.close());
      async.flushMicrotasks();
    });
    return states;
  }

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

  test('a failed first read is unavailable, then retried until it loads', () {
    final states = onFakeTime((async) {
      users.add(member);
      async.flushMicrotasks();
      stored['u1']!.addError(const NetworkFailure());
      async.elapse(retryDelay);
      // A new user is onboarded after all once the retry reads the profile.
      stored['u1']!.add(const UserProfile());
    });
    expect(states, [
      const ProfileState(uid: 'u1'),
      const ProfileState(uid: 'u1', status: ProfileStatus.unavailable),
      loaded('u1', const UserProfile()),
    ]);
    verify(() => profiles.watchProfile('u1')).called(2);
  });

  test('a later stream error keeps the profile and follows it again', () {
    final states = onFakeTime((async) {
      users.add(member);
      async.flushMicrotasks();
      stored['u1']!
        ..add(strong)
        ..addError(const PermissionFailure());
      async.elapse(retryDelay);
      stored['u1']!.add(lean);
    });
    expect(states, [
      const ProfileState(uid: 'u1'),
      loaded('u1', strong),
      loaded('u1', lean),
    ]);
  });

  blocTest<ProfileCubit, ProfileState>(
    'resume follows a failed stream again at once',
    build: () => ProfileCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchProfile: WatchProfile(profiles),
      updateProfile: updateProfile,
      retryDelay: const Duration(hours: 1),
    ),
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!
        ..add(strong)
        ..addError(const NetworkFailure());
      await pumpEventQueue();
      cubit.resume();
      stored['u1']!.add(lean);
    },
    expect: () => [
      const ProfileState(uid: 'u1'),
      loaded('u1', strong),
      loaded('u1', lean),
    ],
    verify: (_) => verify(() => profiles.watchProfile('u1')).called(2),
  );

  test('a retry for a previous user never happens', () {
    final states = onFakeTime((async) {
      users.add(guest);
      async.flushMicrotasks();
      stored['g1']!.addError(const NetworkFailure());
      async.flushMicrotasks();
      users.add(member);
      async.elapse(retryDelay * 2);
    });
    expect(states, [
      const ProfileState(uid: 'g1'),
      const ProfileState(uid: 'g1', status: ProfileStatus.unavailable),
      const ProfileState(uid: 'u1'),
    ]);
    verify(() => profiles.watchProfile('g1')).called(1);
  });

  group('save', () {
    blocTest<ProfileCubit, ProfileState>(
      'saves for the current user without changing the state',
      build: build,
      act: (cubit) async {
        users.add(member);
        await pumpEventQueue();
        await cubit.save(strong, {ProfileField.goal});
      },
      expect: () => [const ProfileState(uid: 'u1')],
      verify: (_) {
        final update =
            verify(() => updateProfile(captureAny())).captured.single
                as ProfileFieldsUpdate;
        expect(update.uid, 'u1');
        expect(update.profile, strong);
        expect(update.fields, {ProfileField.goal});
      },
    );

    blocTest<ProfileCubit, ProfileState>(
      'a rejection is reported once, keeping the profile',
      setUp: () =>
          when(() => updateProfile(any()))
              .thenAnswer((_) async => const Err(PermissionFailure())),
      build: build,
      act: (cubit) async {
        users.add(member);
        await pumpEventQueue();
        stored['u1']!.add(strong);
        await pumpEventQueue();
        await cubit.save(lean, {ProfileField.goal});
        cubit
          ..rejectionShown()
          ..rejectionShown();
      },
      expect: () => [
        const ProfileState(uid: 'u1'),
        loaded('u1', strong),
        const ProfileState(
          uid: 'u1',
          status: ProfileStatus.loaded,
          profile: strong,
          writeRejected: true,
        ),
        loaded('u1', strong),
      ],
    );

    blocTest<ProfileCubit, ProfileState>(
      "a previous user's rejection is not reported",
      build: build,
      act: (cubit) async {
        final answer = Completer<Result<void>>();
        when(() => updateProfile(any())).thenAnswer((_) => answer.future);
        users.add(guest);
        await pumpEventQueue();
        final saving = cubit.save(lean, {ProfileField.goal});
        users.add(member);
        await pumpEventQueue();
        answer.complete(const Err(PermissionFailure()));
        await saving;
      },
      expect: () => [
        const ProfileState(uid: 'g1'),
        const ProfileState(uid: 'u1'),
      ],
    );

    blocTest<ProfileCubit, ProfileState>(
      'saving follows a failed stream again',
      build: () => ProfileCubit(
        watchAuthUser: WatchAuthUser(auth),
        watchProfile: WatchProfile(profiles),
        updateProfile: updateProfile,
        retryDelay: const Duration(hours: 1),
      ),
      act: (cubit) async {
        users.add(member);
        await pumpEventQueue();
        stored['u1']!
          ..add(strong)
          ..addError(const NetworkFailure());
        await pumpEventQueue();
        await cubit.save(lean, {ProfileField.goal});
      },
      verify: (_) => verify(() => profiles.watchProfile('u1')).called(2),
    );

    blocTest<ProfileCubit, ProfileState>(
      'without a user nothing is saved',
      build: build,
      act: (cubit) => cubit.save(lean, {ProfileField.goal}),
      verify: (_) => verifyNever(() => updateProfile(any())),
    );
  });
}
