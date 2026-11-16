import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/body/domain/body_photo_sync.dart';
import 'package:get_workout/features/body/domain/body_repository.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/body/domain/measurement_summary.dart';
import 'package:get_workout/features/body/presentation/measurement_summary_cubit.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:mocktail/mocktail.dart';

import 'body_fakes.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBodyRepository extends Mock implements BodyRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

void main() {
  const user = AuthUser(id: 'u1', isAnonymous: false);
  final now = DateTime.utc(2026, 11, 12);
  const afterFront = 'users/u1/photos/d3/front-3.jpg';
  const afterBack = 'users/u1/photos/d3/back-3.jpg';
  const middleFront = 'users/u1/photos/d2/front-2.jpg';
  final newest = BodyEntry(
    id: 'd3',
    date: DateTime.utc(2026, 11, 10),
    weightKg: 80,
    measurements: const {BodyMeasurement.waist: 84},
    photos: const {PhotoPose.front: afterFront, PhotoPose.back: afterBack},
  );
  final log = BodyEntry(id: 'w', date: DateTime.utc(2026, 11, 5), weightKg: 81);
  final middle = BodyEntry(
    id: 'd2',
    date: DateTime.utc(2026, 10, 1),
    weightKg: 82,
    photos: const {PhotoPose.front: middleFront},
  );
  final oldest = BodyEntry(
    id: 'd1',
    date: DateTime.utc(2026, 6, 1),
    weightKg: 86,
    measurements: const {BodyMeasurement.waist: 90},
  );

  late MockAuthRepository auth;
  late StreamController<AuthUser?> users;
  late StreamController<List<BodyEntry>> entries;
  late StreamController<UserProfile> profiles;
  late FakePhotoStore store;
  late FakeBackup backup;
  late BodyPhotoSync sync;
  late MeasurementSummaryCubit Function(String? afterId) build;
  late MeasurementSummaryCubit cubit;

  setUp(() {
    auth = MockAuthRepository();
    users = StreamController<AuthUser?>.broadcast();
    entries = StreamController<List<BodyEntry>>.broadcast();
    profiles = StreamController<UserProfile>.broadcast();
    final repository = MockBodyRepository();
    final profileRepository = MockProfileRepository();
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => repository.watchEntries(any()))
        .thenAnswer((_) => entries.stream);
    when(() => profileRepository.watchProfile(any()))
        .thenAnswer((_) => profiles.stream);
    store = FakePhotoStore();
    backup = FakeBackup();
    sync = BodyPhotoSync(FakeBackupQueue(), store, backup, FakeBodyRepository())
      ..start(
        users.stream.map(
          (user) => user == null ? null : (id: user.id, guest: false),
        ),
      );
    build = (afterId) => MeasurementSummaryCubit(
      afterId: afterId,
      watchAuthUser: WatchAuthUser(auth),
      watchEntries: WatchBodyEntries(repository),
      watchProfile: WatchProfile(profileRepository),
      findBaseline: const FindBaseline(),
      restorePhoto: RestoreBodyPhoto(sync),
      clock: () => now,
    );
    cubit = build('d3');
  });

  tearDown(() async {
    await cubit.close();
    await sync.cancel();
  });

  Future<void> load(
    List<BodyEntry> list, {
    UserProfile profile = const UserProfile(),
  }) async {
    users.add(user);
    await pumpEventQueue();
    entries.add(list);
    profiles.add(profile);
    await pumpEventQueue();
  }

  test('waits for the entries and the profile', () async {
    users.add(user);
    await pumpEventQueue();
    entries.add([newest, middle]);
    await pumpEventQueue();
    expect(cubit.state.status, MeasurementSummaryStatus.loading);

    profiles.add(const UserProfile());
    await pumpEventQueue();
    expect(cubit.state.status, MeasurementSummaryStatus.ready);
  });

  test('compares with the previous measurement day by default', () async {
    await load([
      newest,
      log,
      middle,
      oldest,
    ], profile: const UserProfile(targetWeightKg: 75));

    final state = cubit.state;
    expect(state.baseline, const PreviousDay());
    expect(state.candidates, [middle, oldest]);
    expect(state.summary!.after, newest);
    expect(state.summary!.before, middle);
    expect(state.summary!.weightKg, (before: 82.0, after: 80.0));
    expect(state.summary!.target!.toGoKg, -5);
  });

  test('the baseline can be the first day or a chosen one', () async {
    await load([newest, log, middle, oldest]);

    cubit.chooseBaseline(const FirstDay());
    expect(cubit.state.baseline, const FirstDay());
    expect(cubit.state.summary!.before, oldest);

    cubit.chooseBaseline(const ChosenDay('d2'));
    expect(cubit.state.baseline, const ChosenDay('d2'));
    expect(cubit.state.summary!.before, middle);

    cubit.chooseBaseline(const PreviousDay());
    expect(cubit.state.summary!.before, middle);
  });

  test('a day with nothing earlier shows alone', () async {
    await load([newest, log]);

    expect(cubit.state.status, MeasurementSummaryStatus.ready);
    expect(cubit.state.summary!.before, isNull);
    expect(cubit.state.candidates, isEmpty);
    expect(cubit.state.summary!.measurements, [
      const MeasurementRow(
        [BodyMeasurement.waist],
        [(before: null, after: 84)],
      ),
    ]);
  });

  test('follows the entries and the profile as they change', () async {
    await load([newest, middle, oldest]);
    cubit.chooseBaseline(const ChosenDay('d1'));

    // The chosen day is deleted: back to the previous day.
    entries.add([newest, middle]);
    await pumpEventQueue();
    expect(cubit.state.baseline, const PreviousDay());
    expect(cubit.state.summary!.before, middle);

    // The baseline is deleted: the day shows alone.
    entries.add([newest]);
    await pumpEventQueue();
    expect(cubit.state.summary!.before, isNull);

    // The day itself is edited.
    final edited = BodyEntry(
      id: 'd3',
      date: newest.date,
      weightKg: 79,
      photos: newest.photos,
    );
    entries.add([edited]);
    await pumpEventQueue();
    expect(cubit.state.summary!.after, edited);

    profiles.add(const UserProfile(targetWeightKg: 75));
    await pumpEventQueue();
    expect(cubit.state.summary!.target!.toGoKg, -4);

    // The day is deleted.
    entries.add([middle]);
    await pumpEventQueue();
    expect(cubit.state.status, MeasurementSummaryStatus.notFound);
  });

  test('a failed stream shows the failure, and retry follows again', () async {
    await load([newest, middle]);
    entries.addError(const NetworkFailure());
    await pumpEventQueue();
    expect(cubit.state.status, MeasurementSummaryStatus.failure);

    cubit.retry();
    entries.add([newest, middle]);
    await pumpEventQueue();
    expect(cubit.state.status, MeasurementSummaryStatus.ready);
  });

  test('a profile that fails still shows the rest', () async {
    users.add(user);
    await pumpEventQueue();
    entries.add([newest, middle]);
    profiles.addError(const NetworkFailure());
    await pumpEventQueue();

    expect(cubit.state.status, MeasurementSummaryStatus.ready);
    expect(cubit.state.summary!.target, isNull);
  });

  test('restores both days\' photos from the backup, then shows the ones '
      'it does not have as unavailable', () async {
    store.files[afterFront] = 'local/$afterFront';
    backup.remote[middleFront] = 'cloud';
    await load([newest, middle]);

    expect(cubit.state.photoFiles, {
      afterFront: 'local/$afterFront',
      middleFront: 'local/$middleFront',
    });
    expect(backup.calls, containsAll(['download $middleFront']));
    // The backup has no copy of the later day's back photo.
    expect(cubit.state.photoFiles.containsKey(afterBack), isFalse);
    expect(cubit.state.fetching, isEmpty);

    // It is not asked for again.
    final calls = backup.calls.length;
    cubit.chooseBaseline(const FirstDay());
    await pumpEventQueue();
    expect(backup.calls.length, calls);
  });

  test('another user starts over', () async {
    await load([newest, middle]);

    users.add(const AuthUser(id: 'u2', isAnonymous: false));
    await pumpEventQueue();
    expect(cubit.state.status, MeasurementSummaryStatus.loading);

    entries.add([middle]);
    profiles.add(const UserProfile());
    await pumpEventQueue();
    expect(cubit.state.status, MeasurementSummaryStatus.notFound);
  });

  group('without a given day', () {
    setUp(() async {
      await cubit.close();
      cubit = build(null);
    });

    test('compares the newest measurement day with the previous', () async {
      await load([newest, log, middle, oldest]);

      expect(cubit.state.summary!.after, newest);
      expect(cubit.state.summary!.before, middle);
      // The later days after the earlier one.
      expect(cubit.state.laterCandidates, [newest]);
    });

    test('the later day can be chosen; the baseline follows it', () async {
      await load([newest, log, middle, oldest]);
      cubit.chooseBaseline(const ChosenDay('d2'));

      cubit.chooseAfter('d2');

      expect(cubit.state.summary!.after, middle);
      // The chosen day is no longer earlier: back to the previous one.
      expect(cubit.state.baseline, const PreviousDay());
      expect(cubit.state.summary!.before, oldest);
      expect(cubit.state.candidates, [oldest]);
    });

    test('a chosen day that is gone gives the newest again', () async {
      await load([newest, middle, oldest]);
      cubit.chooseAfter('d2');

      entries.add([newest, oldest]);
      await pumpEventQueue();

      expect(cubit.state.summary!.after, newest);
      expect(cubit.state.summary!.before, oldest);
    });

    test(
      'one measurement day shows alone; none shows there are none',
      () async {
        await load([newest, log]);
        expect(cubit.state.status, MeasurementSummaryStatus.ready);
        expect(cubit.state.summary!.after, newest);
        expect(cubit.state.summary!.before, isNull);
        expect(cubit.state.laterCandidates, isEmpty);

        entries.add([log]);
        await pumpEventQueue();
        expect(cubit.state.status, MeasurementSummaryStatus.noMeasurementDays);
      },
    );

    test('a day a link shows is not found once it is gone', () async {
      await load([newest, middle, oldest]);
      cubit.showDay('d2');
      expect(cubit.state.summary!.after, middle);

      entries.add([newest, oldest]);
      await pumpEventQueue();
      expect(cubit.state.status, MeasurementSummaryStatus.notFound);

      // Picking a day ends what the link asked for.
      cubit.chooseAfter('d3');
      expect(cubit.state.summary!.after, newest);
    });
  });
}
