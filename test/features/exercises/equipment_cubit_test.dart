import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../fake_time.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockUserLibraryRepository extends Mock implements UserLibraryRepository {}

void main() {
  const guest = AuthUser(id: 'g1', isAnonymous: true);
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  const failure = NetworkFailure();
  const dumbbells = {Equipment.dumbbell, Equipment.bench};
  const barbell = {Equipment.barbell};
  const retryDelay = Duration(milliseconds: 20);

  late MockAuthRepository auth;
  late MockUserLibraryRepository library;
  late StreamController<AuthUser?> users;

  /// Every subscription to a user's equipment, oldest first.
  late Map<String, List<StreamController<Set<Equipment>?>>> watched;

  StreamController<Set<Equipment>?> latest(String uid) => watched[uid]!.last;

  setUpAll(() => registerFallbackValue(<Equipment>{}));

  setUp(() {
    auth = MockAuthRepository();
    library = MockUserLibraryRepository();
    users = StreamController<AuthUser?>();
    watched = {};
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => library.watchEquipment(any())).thenAnswer((call) {
      final controller = StreamController<Set<Equipment>?>();
      watched
          .putIfAbsent(call.positionalArguments.first as String, () => [])
          .add(controller);
      return controller.stream;
    });
  });

  EquipmentCubit build({Duration delay = retryDelay}) => EquipmentCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchEquipment: WatchOwnedEquipment(library),
    saveEquipment: SaveOwnedEquipment(library),
    retryDelay: delay,
  );

  void savesReturn(Future<Result<void>> Function() result) =>
      when(() => library.saveEquipment(any(), any()))
          .thenAnswer((_) => result());

  Future<void> signIn(AuthUser user, Set<Equipment>? owned) async {
    users.add(user);
    await pumpEventQueue();
    latest(user.id).add(owned);
    await pumpEventQueue();
  }

  test('starts unknown', () {
    expect(build().state, const EquipmentState(null));
  });

  blocTest<EquipmentCubit, EquipmentState>(
    'follows whoever is signed in and resets at once on a user change',
    build: build,
    act: (_) async {
      await signIn(guest, dumbbells);
      users.add(member);
      await pumpEventQueue();
      latest('u1').add(barbell);
      await pumpEventQueue();
      latest('g1').add({});
    },
    expect: () => [
      const EquipmentState(dumbbells),
      const EquipmentState(null),
      const EquipmentState(barbell),
    ],
    verify: (_) => expect(latest('g1').hasListener, isFalse),
  );

  blocTest<EquipmentCubit, EquipmentState>(
    'save stores the choice for the current user, without bodyweight',
    setUp: () => savesReturn(() async => const Ok(null)),
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      await cubit.save({Equipment.bodyweight, ...dumbbells});
    },
    expect: () => const <EquipmentState>[],
    verify: (_) =>
        verify(() => library.saveEquipment('u1', dumbbells)).called(1),
  );

  blocTest<EquipmentCubit, EquipmentState>(
    'a failed save keeps the equipment and reports the failure',
    setUp: () => savesReturn(() async => const Err(failure)),
    build: build,
    act: (cubit) async {
      await signIn(member, barbell);
      await cubit.save(dumbbells);
    },
    expect: () => [
      const EquipmentState(barbell),
      const EquipmentState(barbell, failure: failure),
    ],
  );

  test('a failed stream is followed again after a backoff', () {
    final states = onFakeTime(build, (async, _) {
      users.add(member);
      async.flushMicrotasks();
      latest('u1').add(barbell);
      latest('u1').addError(const PermissionFailure());
      async.flushMicrotasks();
      expect(watched['u1'], hasLength(1));

      async.elapse(retryDelay);
      expect(watched['u1'], hasLength(2));
      latest('u1').add(dumbbells);
    });
    expect(states, [
      const EquipmentState(barbell),
      const EquipmentState(dumbbells),
    ]);
  });

  blocTest<EquipmentCubit, EquipmentState>(
    'a save while the stream is down follows the stream again at once',
    setUp: () => savesReturn(() async => const Ok(null)),
    build: () => build(delay: const Duration(hours: 1)),
    act: (cubit) async {
      await signIn(member, barbell);
      latest('u1').addError(const NetworkFailure());
      await pumpEventQueue();

      await cubit.save(dumbbells);
      expect(watched['u1'], hasLength(2));
      latest('u1').add(dumbbells);
    },
    expect: () => [
      const EquipmentState(barbell),
      const EquipmentState(dumbbells),
    ],
  );

  final write = Completer<Result<void>>();
  blocTest<EquipmentCubit, EquipmentState>(
    "a save's outcome is ignored once another user is signed in",
    setUp: () => savesReturn(() => write.future),
    build: build,
    act: (cubit) async {
      await signIn(guest, barbell);
      final saved = cubit.save(dumbbells);
      await signIn(member, null);
      write.complete(const Err(failure));
      await saved;
    },
    expect: () => [const EquipmentState(barbell), const EquipmentState(null)],
  );

  blocTest<EquipmentCubit, EquipmentState>(
    'save without a user stores nothing',
    build: build,
    act: (cubit) => cubit.save(dumbbells),
    expect: () => const <EquipmentState>[],
    verify: (_) => verifyNever(() => library.saveEquipment(any(), any())),
  );
}
