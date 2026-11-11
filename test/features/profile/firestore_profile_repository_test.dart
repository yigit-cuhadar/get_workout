import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/data/firestore_profile_repository.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreProfileRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreProfileRepository(firestore);
  });

  DocumentReference<Map<String, dynamic>> user() =>
      firestore.collection('users').doc('u1');

  Future<Map<String, dynamic>?> stored() async => (await user().get()).data();

  const answers = UserProfile(
    goal: Goal.buildMuscle,
    level: Level.intermediate,
    daysPerWeek: 4,
    equipment: {Equipment.dumbbell, Equipment.barbell},
    sex: Sex.female,
    birthYear: 1990,
    heightCm: 170,
    weightKg: 65.5,
    targetWeightKg: 60,
  );

  test('a missing document gives an empty profile', () async {
    expect(await repository.watchProfile('u1').first, const UserProfile());
  });

  test('a document without a profile map gives an empty profile', () async {
    await user().set({
      'settings': {'weightUnit': 'kg'},
    });
    expect(await repository.watchProfile('u1').first, const UserProfile());
  });

  test('saved answers are stored with their codes and read back', () async {
    final result = await repository.saveFields(
      'u1',
      answers,
      ProfileField.values.toSet(),
    );

    expect(result.isOk, isTrue);
    expect(await stored(), {
      'profile': {
        'goal': 'build_muscle',
        'level': 'intermediate',
        'daysPerWeek': 4,
        'sex': 'female',
        'birthYear': 1990,
        'heightCm': 170.0,
        'weightKg': 65.5,
        'targetWeightKg': 60.0,
      },
    });
    expect(
      await repository.watchProfile('u1').first,
      answers.without(ProfileField.equipment),
    );
  });

  test('never writes the equipment, which the library owns', () async {
    await user().set({
      'profile': {
        'equipment': ['kettlebell', 'hoverboard'],
      },
    });

    await repository.saveFields('u1', answers, ProfileField.values.toSet());
    await repository.completeOnboarding('u1', answers);

    final profile = (await stored())!['profile'] as Map;
    expect(profile['equipment'], ['kettlebell', 'hoverboard']);
  });

  test('saving a field keeps every other field of the document', () async {
    await user().set({
      'profile': {
        'equipment': ['kettlebell'],
        'goal': 'lose_fat',
      },
      'settings': {'weightUnit': 'lb'},
      'favoriteExerciseIds': ['e1'],
    });

    await repository.saveFields('u1', answers, {ProfileField.height});

    expect(await stored(), {
      'profile': {
        'equipment': ['kettlebell'],
        'goal': 'lose_fat',
        'heightCm': 170.0,
      },
      'settings': {'weightUnit': 'lb'},
      'favoriteExerciseIds': ['e1'],
    });
  });

  test('saving an unanswered field removes it', () async {
    await repository.saveFields('u1', answers, ProfileField.values.toSet());

    await repository.saveFields(
      'u1',
      answers.without(ProfileField.targetWeight),
      {ProfileField.targetWeight},
    );

    final profile = (await stored())!['profile'] as Map;
    expect(profile.containsKey('targetWeightKg'), isFalse);
    expect(profile['weightKg'], 65.5);
  });

  test(
    'stored equipment is read without bodyweight or unknown codes',
    () async {
      await user().set({
        'profile': {
          'equipment': ['bodyweight', 'hoverboard', 'dumbbell'],
        },
      });
      expect((await repository.watchProfile('u1').first).equipment, {
        Equipment.dumbbell,
      });
    },
  );

  test('an empty equipment list is bodyweight only', () async {
    await user().set({
      'profile': {'equipment': <String>[]},
    });
    expect((await repository.watchProfile('u1').first).equipment, isEmpty);
  });

  group('completing onboarding', () {
    test('stores the answers given and the completion time', () async {
      await repository.completeOnboarding(
        'u1',
        const UserProfile(goal: Goal.getStronger, daysPerWeek: 3),
      );

      final profile = (await stored())!['profile'] as Map;
      expect(profile['goal'], 'get_stronger');
      expect(profile['daysPerWeek'], 3);
      expect(profile['onboardingCompletedAt'], isA<Timestamp>());
      expect(profile.containsKey('sex'), isFalse);
      expect(
        (await repository.watchProfile('u1').first).onboardingCompleted,
        isTrue,
      );
    });

    test('keeps what it was not given, also from other features', () async {
      await user().set({
        'profile': {
          'equipment': ['dumbbell'],
          'weightKg': 80,
        },
        'settings': {'lengthUnit': 'in'},
        'favoriteExerciseIds': ['e1'],
      });

      await repository.completeOnboarding(
        'u1',
        const UserProfile(goal: Goal.loseFat),
      );

      final data = (await stored())!;
      final profile = data['profile'] as Map;
      expect(profile['equipment'], ['dumbbell']);
      expect(profile['weightKg'], 80);
      expect(profile['goal'], 'lose_fat');
      expect(data['settings'], {'lengthUnit': 'in'});
      expect(data['favoriteExerciseIds'], ['e1']);
    });

    test('a completion time still pending on the server counts', () async {
      await user().set({
        'profile': {'onboardingCompletedAt': null},
      });

      expect(
        (await repository.watchProfile('u1').first).onboardingCompleted,
        isTrue,
      );
    });
  });

  test('malformed and unknown values read as unanswered', () async {
    await user().set({
      'profile': {
        'goal': 'get_huge',
        'level': 3,
        'daysPerWeek': 'four',
        'equipment': ['dumbbell', 'hoverboard', 'bodyweight', 7],
        'sex': 'other',
        'birthYear': '1990',
        'heightCm': 180,
        'weightKg': null,
        'onboardingCompletedAt': 'yesterday',
      },
    });

    expect(
      await repository.watchProfile('u1').first,
      const UserProfile(equipment: {Equipment.dumbbell}, heightCm: 180),
    );
  });

  test('the stream emits every change', () async {
    const goal = UserProfile(goal: Goal.generalFitness);
    final expectation = expectLater(
      repository.watchProfile('u1'),
      emitsInOrder([const UserProfile(), goal]),
    );

    await repository.saveFields('u1', goal, {ProfileField.goal});

    await expectation;
  });
}
