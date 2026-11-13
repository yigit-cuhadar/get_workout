import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_photo_sync.dart';
import 'package:get_workout/features/body/domain/body_photos.dart';
import 'package:get_workout/features/body/domain/body_repository.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/programs/domain/premium_status.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/strength/domain/strength.dart';
import 'package:mocktail/mocktail.dart';

import 'body_fakes.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBodyRepository extends Mock implements BodyRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

class FakePremium implements PremiumStatus {
  final controller = StreamController<bool?>.broadcast();

  @override
  Stream<bool?> watch() => controller.stream;
}

void main() {
  const user = AuthUser(id: 'u1', isAnonymous: true);
  final now = DateTime(2026, 11, 12, 9);
  const frontPath = 'users/u1/photos/old/front-1.jpg';
  final recent = BodyEntry(id: 'r', date: DateTime(2026, 11, 10), weightKg: 80);
  final old = BodyEntry(
    id: 'old',
    date: DateTime(2026, 3, 1),
    weightKg: 86,
    photos: const {PhotoPose.front: frontPath},
  );

  late MockAuthRepository auth;
  late MockBodyRepository repository;
  late FakePhotoStore store;
  late FakeBackup backup;
  late FakeBackupQueue queue;
  late FakePremium premium;
  late StreamController<AuthUser?> users;
  late StreamController<List<BodyEntry>> entries;
  late StreamController<Failure> rejected;
  late StreamController<UserProfile> profiles;
  late BodyPhotoSync sync;
  late BodyPhotoWorld deletes;
  late BodyListCubit cubit;

  setUpAll(() {
    registerFallbackValue(BodyEntry(id: 'x', date: DateTime(2026)));
  });

  setUp(() {
    auth = MockAuthRepository();
    repository = MockBodyRepository();
    store = FakePhotoStore();
    backup = FakeBackup();
    premium = FakePremium();
    users = StreamController<AuthUser?>.broadcast();
    entries = StreamController<List<BodyEntry>>.broadcast();
    rejected = StreamController<Failure>.broadcast();
    profiles = StreamController<UserProfile>.broadcast();
    final profileRepository = MockProfileRepository();
    when(() => profileRepository.watchProfile(any()))
        .thenAnswer((_) => profiles.stream);
    deletes = BodyPhotoWorld();
    queue = FakeBackupQueue();
    sync = BodyPhotoSync(queue, store, backup, deletes.repository)
      ..start(
        users.stream.map(
          (user) =>
              user == null ? null : (id: user.id, guest: user.isAnonymous),
        ),
      );
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => repository.watchEntries(any()))
        .thenAnswer((_) => entries.stream);
    when(() => repository.rejectedWrites).thenAnswer((_) => rejected.stream);
    cubit = BodyListCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchEntries: WatchBodyEntries(repository),
      watchRejectedWrites: WatchRejectedBodyWrites(repository),
      watchPremium: WatchPremium(premium),
      watchProfile: WatchProfile(profileRepository),
      findPhotos: FindBodyPhotos(store),
      restorePhoto: RestoreBodyPhoto(sync),
      reconcilePhotos: ReconcileBodyPhotos(sync),
      // Deletes go to an in-memory repository; the mock above feeds the list.
      deleteEntry: deletes.delete(),
      clock: () => now,
    );
  });

  tearDown(() async {
    await cubit.close();
    await sync.cancel();
  });

  Future<void> signIn() async {
    users.add(user);
    await pumpEventQueue();
  }

  Future<void> receive(List<BodyEntry> list) async {
    entries.add(list);
    await pumpEventQueue();
  }

  test('loads the signed-in user\'s entries with a 12-week range', () async {
    await signIn();
    expect(cubit.state.status, BodyListStatus.loading);

    await receive([recent, old]);

    expect(cubit.state.status, BodyListStatus.ready);
    expect(cubit.state.entries, [recent, old]);
    expect(cubit.state.range, StrengthRange.weeks12);
  });

  test(
    'a free user is told of older entries; Premium widens the range',
    () async {
      await signIn();
      await receive([recent, old]);
      premium.controller.add(false);
      await pumpEventQueue();
      expect(cubit.state.olderLocked, isTrue);

      cubit.selectRange(StrengthRange.all);
      expect(cubit.state.range, StrengthRange.weeks12);

      premium.controller.add(true);
      await pumpEventQueue();
      expect(cubit.state.range, StrengthRange.all);
      expect(cubit.state.olderLocked, isFalse);
    },
  );

  group('body fat', () {
    BodyEntry measured(String id, DateTime date, double abdomen) => BodyEntry(
      id: id,
      date: date,
      measurements: {
        BodyMeasurement.neck: 38,
        BodyMeasurement.abdomen: abdomen,
      },
    );
    final newer = measured('n', DateTime(2026, 11, 1), 85);
    final older = measured('o', DateTime(2026, 2, 1), 95);
    const man = UserProfile(sex: Sex.male, heightCm: 180);

    Future<void> profile(UserProfile profile) async {
      profiles.add(profile);
      await pumpEventQueue();
    }

    test('follows the profile; entries without one are left out', () async {
      await signIn();
      await receive([newer, recent, older]);
      expect(cubit.state.bodyFat, isEmpty);

      await profile(man);

      expect(cubit.state.bodyFat.keys, {'n', 'o'});
      expect(cubit.state.bodyFat['n']!, lessThan(cubit.state.bodyFat['o']!));

      await profile(const UserProfile(sex: Sex.male));
      expect(cubit.state.bodyFat, isEmpty);
    });

    test('another user starts without the previous profile', () async {
      await signIn();
      await profile(man);
      users.add(const AuthUser(id: 'u2', isAnonymous: true));
      await pumpEventQueue();

      await receive([newer]);

      expect(cubit.state.bodyFat, isEmpty);
    });
  });

  test('photo files on the device follow the entries', () async {
    store.files[frontPath] = 'local/front';
    await signIn();

    await receive([recent, old]);

    expect(cubit.state.photoFiles, {frontPath: 'local/front'});
  });

  test('photos on the device unknown to the backup are queued', () async {
    store.files[frontPath] = 'local/front';
    await signIn();

    await receive([recent, old]);

    expect(backup.remote, {frontPath: 'local/front'});
    expect(queue.saved, {frontPath: BackupState.uploaded});
  });

  test('a restore finishing during a look for files is kept', () async {
    backup.remote[frontPath] = 'cloud';
    await signIn();
    final slowLook = store.findGate = Completer<void>();
    // The look for files starts with the snapshot; the restore lands
    // before it reports.
    await receive([recent, old]);
    await cubit.restore([frontPath]);
    slowLook.complete();
    await pumpEventQueue();

    expect(cubit.state.photoFiles, {frontPath: 'local/$frontPath'});
  });

  test('restore fetches a missing photo from the backup', () async {
    backup.remote[frontPath] = 'cloud';
    await signIn();
    await receive([recent, old]);
    expect(cubit.state.photoFiles, isEmpty);

    await cubit.restore([frontPath]);

    expect(cubit.state.photoFiles, {frontPath: 'local/$frontPath'});
  });

  test('a failed stream shows the failure; another user starts over', () async {
    await signIn();
    entries.addError(const NetworkFailure());
    await pumpEventQueue();
    expect(cubit.state.status, BodyListStatus.failure);

    users.add(null);
    await pumpEventQueue();
    expect(cubit.state, const BodyListState());
  });

  test('a rejected write is flagged until shown', () async {
    await signIn();
    rejected.add(const PermissionFailure());
    await pumpEventQueue();
    expect(cubit.state.writeRejected, isTrue);

    cubit.rejectionShown();
    expect(cubit.state.writeRejected, isFalse);
  });

  test('delete removes the entry for the signed-in user', () async {
    await signIn();

    expect(await cubit.delete(old), isNull);

    expect(deletes.repository.calls, ['delete old']);
  });
}
