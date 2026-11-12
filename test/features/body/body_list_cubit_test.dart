import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_photo_sync.dart';
import 'package:get_workout/features/body/domain/body_repository.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/programs/domain/premium_status.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/strength/domain/strength.dart';
import 'package:mocktail/mocktail.dart';

import 'body_fakes.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBodyRepository extends Mock implements BodyRepository {}

class FakePremium implements PremiumStatus {
  final controller = StreamController<bool?>.broadcast();

  @override
  Stream<bool?> watch() => controller.stream;
}

void main() {
  const user = AuthUser(id: 'u1', isAnonymous: true);
  final now = DateTime(2026, 11, 12, 9);
  const frontPath = 'users/u1/photos/old/front.jpg';
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
  late FakePremium premium;
  late StreamController<AuthUser?> users;
  late StreamController<List<BodyEntry>> entries;
  late StreamController<Failure> rejected;
  late BodyPhotoSync sync;
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
    sync = BodyPhotoSync(FakeBackupQueue(), store, backup)
      ..start(users.stream.map((user) => user?.id));
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => repository.watchEntries(any()))
        .thenAnswer((_) => entries.stream);
    when(() => repository.rejectedWrites).thenAnswer((_) => rejected.stream);
    when(() => repository.deleteEntry(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    cubit = BodyListCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchEntries: WatchBodyEntries(repository),
      watchRejectedWrites: WatchRejectedBodyWrites(repository),
      watchPremium: WatchPremium(premium),
      findPhotos: FindBodyPhotos(store),
      restorePhoto: RestoreBodyPhoto(sync),
      deleteEntry: DeleteBodyEntry(repository, store, sync),
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

  test('loads the signed-in user\'s entries with a 12-week chart', () async {
    await signIn();
    expect(cubit.state.status, BodyListStatus.loading);

    await receive([recent, old]);

    expect(cubit.state.status, BodyListStatus.ready);
    expect(cubit.state.entries, [recent, old]);
    expect(cubit.state.range, StrengthRange.weeks12);
    expect(cubit.state.points, [(date: recent.date, kg: 80.0)]);
  });

  test(
    'a free user is told of older weights; Premium widens the range',
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
      expect(cubit.state.points, hasLength(2));
      expect(cubit.state.olderLocked, isFalse);
    },
  );

  test('photo files on the device follow the entries', () async {
    store.files[frontPath] = 'local/front';
    await signIn();

    await receive([recent, old]);

    expect(cubit.state.photoFiles, {frontPath: 'local/front'});
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

    verify(() => repository.deleteEntry('u1', 'old')).called(1);
  });
}
