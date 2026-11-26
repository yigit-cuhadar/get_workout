import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/data/firestore_user_library_repository.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreUserLibraryRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreUserLibraryRepository(firestore);
  });

  DocumentReference<Map<String, dynamic>> user() =>
      firestore.collection('users').doc('u1');

  group('equipment', () {
    test('is unknown while the document or the field is missing', () async {
      expect(await repository.watchEquipment('u1').first, isNull);
      await user().set({
        'profile': {'goal': 'get_stronger'},
      });
      expect(await repository.watchEquipment('u1').first, isNull);
    });

    test('an empty list is a choice: bodyweight only', () async {
      await user().set({
        'profile': {'equipment': <String>[]},
      });
      expect(await repository.watchEquipment('u1').first, <Equipment>{});
    });

    test('unknown codes and bodyweight are dropped', () async {
      await user().set({
        'profile': {
          'equipment': ['dumbbell', 'hoverboard', 'bodyweight', 'bench'],
        },
      });
      expect(await repository.watchEquipment('u1').first, {
        Equipment.dumbbell,
        Equipment.bench,
      });
    });

    test('save merges into the profile and keeps every other field', () async {
      await user().set({
        'profile': {
          'goal': 'get_stronger',
          'equipment': ['barbell'],
        },
        'settings': {'weightUnit': 'kg'},
        'favoriteExerciseIds': ['squat'],
      });

      final result = await repository.saveEquipment('u1', {
        Equipment.bench,
        Equipment.dumbbell,
      });

      expect(result.isOk, isTrue);
      expect((await user().get()).data(), {
        'profile': {
          'goal': 'get_stronger',
          // Stored in vocabulary order.
          'equipment': ['dumbbell', 'bench'],
        },
        'settings': {'weightUnit': 'kg'},
        'favoriteExerciseIds': ['squat'],
      });
    });

    test('save keeps codes this version does not know', () async {
      await user().set({
        'profile': {
          'equipment': ['hoverboard', 'barbell', 'bodyweight', 'bench'],
        },
      });

      await repository.saveEquipment('u1', {
        Equipment.bench,
        Equipment.dumbbell,
        Equipment.bodyweight,
      });

      expect((await user().get()).data(), {
        'profile': {
          'equipment': ['hoverboard', 'bench', 'dumbbell'],
        },
      });
    });

    test('saving nothing is still a choice', () async {
      await repository.saveEquipment('u1', {});

      expect((await user().get()).data(), {
        'profile': {'equipment': <String>[]},
      });
      expect(await repository.watchEquipment('u1').first, <Equipment>{});
    });

    test('save creates the document when it is missing', () async {
      await repository.saveEquipment('u1', {Equipment.kettlebell});
      expect(await repository.watchEquipment('u1').first, {
        Equipment.kettlebell,
      });
    });
  });

  group('favourites', () {
    test('are empty while the document or the field is missing', () async {
      expect(await repository.watchFavorites('u1').first, <String>{});
      await user().set({
        'settings': {'weightUnit': 'kg'},
      });
      expect(await repository.watchFavorites('u1').first, <String>{});
    });

    test('adding keeps the others and never duplicates', () async {
      await user().set({
        'favoriteExerciseIds': ['squat'],
        'profile': {'goal': 'get_stronger'},
      });

      await repository.setFavorite('u1', 'bench', favorite: true);
      await repository.setFavorite('u1', 'bench', favorite: true);

      expect((await user().get()).data(), {
        'favoriteExerciseIds': ['squat', 'bench'],
        'profile': {'goal': 'get_stronger'},
      });
    });

    test('removing takes out only that one', () async {
      await user().set({
        'favoriteExerciseIds': ['squat', 'bench'],
        'settings': {'weightUnit': 'kg'},
      });

      final result = await repository.setFavorite(
        'u1',
        'squat',
        favorite: false,
      );

      expect(result.isOk, isTrue);
      expect((await user().get()).data(), {
        'favoriteExerciseIds': ['bench'],
        'settings': {'weightUnit': 'kg'},
      });
    });

    test('adding to a missing document creates it', () async {
      await repository.setFavorite('u1', 'squat', favorite: true);
      expect(await repository.watchFavorites('u1').first, {'squat'});
    });

    test('the stream emits every change', () async {
      final emitted = repository.watchFavorites('u1');
      final expectation = expectLater(
        emitted,
        emitsInOrder([
          <String>{},
          {'squat'},
          <String>{},
        ]),
      );

      await repository.setFavorite('u1', 'squat', favorite: true);
      await repository.setFavorite('u1', 'squat', favorite: false);

      await expectation;
    });
  });
}
