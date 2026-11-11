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

class MockAuthRepository extends Mock implements AuthRepository {}

class MockUserLibraryRepository extends Mock implements UserLibraryRepository {}

void main() {
  const guest = AuthUser(id: 'g1', isAnonymous: true);
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  const failure = NetworkFailure();
  const dumbbells = {Equipment.dumbbell, Equipment.bench};
  const barbell = {Equipment.barbell};

  late MockAuthRepository auth;
  late MockUserLibraryRepository library;
  late StreamController<AuthUser?> users;
  late Map<String, StreamController<Set<Equipment>?>> stored;

  setUpAll(() => registerFallbackValue(<Equipment>{}));

  setUp(() {
    auth = MockAuthRepository();
    library = MockUserLibraryRepository();
    users = StreamController<AuthUser?>();
    stored = {};
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => library.watchEquipment(any())).thenAnswer(
      (call) => stored
          .putIfAbsent(
            call.positionalArguments.first as String,
            StreamController<Set<Equipment>?>.new,
          )
          .stream,
    );
  });

  EquipmentCubit build() => EquipmentCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchEquipment: WatchOwnedEquipment(library),
    saveEquipment: SaveOwnedEquipment(library),
  );

  test('starts unknown', () {
    expect(build().state, const EquipmentState(null));
  });

  blocTest<EquipmentCubit, EquipmentState>(
    'follows whoever is signed in and resets at once on a user change',
    build: build,
    act: (_) async {
      users.add(guest);
      await pumpEventQueue();
      stored['g1']!.add(dumbbells);
      await pumpEventQueue();
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add(barbell);
      await pumpEventQueue();
      stored['g1']!.add({});
    },
    expect: () => [
      const EquipmentState(dumbbells),
      const EquipmentState(null),
      const EquipmentState(barbell),
    ],
    verify: (_) => expect(stored['g1']!.hasListener, isFalse),
  );

  blocTest<EquipmentCubit, EquipmentState>(
    'save stores the choice for the current user, without bodyweight',
    setUp: () =>
        when(() => library.saveEquipment(any(), any()))
            .thenAnswer((_) async => const Ok(null)),
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
    setUp: () =>
        when(() => library.saveEquipment(any(), any()))
            .thenAnswer((_) async => const Err(failure)),
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add(barbell);
      await pumpEventQueue();
      await cubit.save(dumbbells);
    },
    expect: () => [
      const EquipmentState(barbell),
      const EquipmentState(barbell, failure: failure),
    ],
  );

  blocTest<EquipmentCubit, EquipmentState>(
    'a stream error keeps the last equipment',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!
        ..add(barbell)
        ..addError(const PermissionFailure());
    },
    expect: () => [const EquipmentState(barbell)],
  );

  blocTest<EquipmentCubit, EquipmentState>(
    'save without a user stores nothing',
    build: build,
    act: (cubit) => cubit.save(dumbbells),
    expect: () => const <EquipmentState>[],
    verify: (_) => verifyNever(() => library.saveEquipment(any(), any())),
  );
}
