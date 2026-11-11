import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:mocktail/mocktail.dart';

class MockProfileRepository extends Mock implements ProfileRepository {}

class MockUserLibraryRepository extends Mock implements UserLibraryRepository {}

void main() {
  late MockProfileRepository profiles;
  late MockUserLibraryRepository library;
  late UpdateProfile update;

  setUpAll(() {
    registerFallbackValue(const UserProfile());
    registerFallbackValue(<ProfileField>{});
    registerFallbackValue(<Equipment>{});
  });

  setUp(() {
    profiles = MockProfileRepository();
    library = MockUserLibraryRepository();
    when(() => profiles.saveFields(any(), any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => library.saveEquipment(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    update = UpdateProfile(profiles, SaveOwnedEquipment(library));
  });

  const answers = UserProfile(
    goal: Goal.loseFat,
    equipment: {Equipment.dumbbell},
  );

  test('the equipment is saved only through the library', () async {
    final result = await update((
      uid: 'u1',
      profile: answers,
      fields: {ProfileField.equipment},
    ));

    expect(result.isOk, isTrue);
    verify(() => library.saveEquipment('u1', {Equipment.dumbbell})).called(1);
    verifyZeroInteractions(profiles);
  });

  test('other answers are saved only through the profile', () async {
    await update((uid: 'u1', profile: answers, fields: {ProfileField.goal}));

    verify(() => profiles.saveFields('u1', answers, {ProfileField.goal}))
        .called(1);
    verifyZeroInteractions(library);
  });

  test('either failure fails the update', () async {
    when(() => library.saveEquipment(any(), any()))
        .thenAnswer((_) async => const Err(PermissionFailure()));

    final result = await update((
      uid: 'u1',
      profile: answers,
      fields: {ProfileField.goal, ProfileField.equipment},
    ));

    expect(result.failureOrNull, isA<PermissionFailure>());
    verify(() => profiles.saveFields('u1', answers, {ProfileField.goal}))
        .called(1);
  });
}
