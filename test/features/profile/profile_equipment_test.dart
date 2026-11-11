import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/data/firestore_user_library_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/data/firestore_profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';

/// The profile and the exercise library share `profile.equipment` of
/// `users/{uid}`; the library's repository is its only writer.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreProfileRepository profiles;
  late FirestoreUserLibraryRepository library;
  late UpdateProfile updateProfile;
  late CompleteOnboarding completeOnboarding;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    profiles = FirestoreProfileRepository(firestore);
    library = FirestoreUserLibraryRepository(firestore);
    final saveEquipment = SaveOwnedEquipment(library);
    updateProfile = UpdateProfile(profiles, saveEquipment);
    completeOnboarding = CompleteOnboarding(profiles, saveEquipment);
  });

  DocumentReference<Map<String, dynamic>> user() =>
      firestore.collection('users').doc('u1');

  test('equipment answered in onboarding reaches the library live', () async {
    final owned = library.watchEquipment('u1');
    final expectation = expectLater(
      owned,
      // The fake emits after each write of the library's batch, Firestore
      // once; only the outcome matters.
      emitsInOrder([
        isNull,
        emitsThrough({Equipment.dumbbell, Equipment.bench}),
      ]),
    );

    await completeOnboarding((
      uid: 'u1',
      answers: const UserProfile(
        goal: Goal.loseFat,
        equipment: {Equipment.bench, Equipment.dumbbell},
      ),
    ));

    await expectation;
    final profile = (await user().get()).data()!['profile'] as Map;
    expect(profile['goal'], 'lose_fat');
    expect(profile['onboardingCompletedAt'], isA<Timestamp>());
  });

  test('equipment edited in the profile reaches the library live', () async {
    await library.saveEquipment('u1', {Equipment.barbell});
    final expectation = expectLater(
      library.watchEquipment('u1'),
      emitsInOrder([
        {Equipment.barbell},
        emitsThrough({Equipment.kettlebell}),
      ]),
    );

    await updateProfile((
      uid: 'u1',
      profile: const UserProfile(equipment: {Equipment.kettlebell}),
      fields: {ProfileField.equipment},
    ));

    await expectation;
  });

  test('equipment saved by the library reaches the profile live', () async {
    final expectation = expectLater(
      profiles.watchProfile('u1').map((profile) => profile.equipment),
      emitsInOrder([
        isNull,
        emitsThrough({Equipment.cable}),
        emitsThrough(<Equipment>{}),
      ]),
    );

    await library.saveEquipment('u1', {Equipment.cable});
    await library.saveEquipment('u1', {});

    await expectation;
  });

  test('profile writes keep codes of newer app versions and never store '
      'bodyweight', () async {
    await user().set({
      'profile': {
        'equipment': ['dumbbell', 'hoverboard'],
      },
    });

    await updateProfile((
      uid: 'u1',
      profile: const UserProfile(
        equipment: {Equipment.barbell, Equipment.bodyweight},
      ),
      fields: {ProfileField.equipment},
    ));
    await completeOnboarding((
      uid: 'u1',
      answers: const UserProfile(
        equipment: {Equipment.barbell, Equipment.cable},
      ),
    ));

    final stored = (await user().get()).data()!['profile'] as Map;
    expect(
      stored['equipment'],
      unorderedEquals(['hoverboard', 'barbell', 'cable']),
    );
    expect((await profiles.watchProfile('u1').first).equipment, {
      Equipment.barbell,
      Equipment.cable,
    });
  });

  test('saving other answers leaves the equipment alone', () async {
    await library.saveEquipment('u1', {Equipment.rings});

    await updateProfile((
      uid: 'u1',
      profile: const UserProfile(sex: Sex.male),
      fields: {ProfileField.sex, ProfileField.equipment},
    ));

    expect(await library.watchEquipment('u1').first, {Equipment.rings});
  });
}
