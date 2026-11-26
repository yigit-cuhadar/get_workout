import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/data/firestore_exercise_repository.dart';
import 'package:get_workout/features/exercises/data/firestore_exercise_source.dart';
import 'package:get_workout/features/exercises/domain/exercise_animation.dart';
import 'package:mocktail/mocktail.dart';

class MockSource extends Mock implements FirestoreExerciseSource {}

const recipeText =
    '{"gear":[{"kit":"barbell"}],"keys":[[0,"top"],[1.6,"bottom"],[2,"top"]],'
    '"poses":{"bottom":{},"top":{}}}';
const kitsText = '{"barbell":{"pieces":[]}}';

const animation = ExerciseAnimation(
  recipe: {
    'gear': [
      {'kit': 'barbell'},
    ],
    'keys': [
      [0, 'top'],
      [1.6, 'bottom'],
      [2, 'top'],
    ],
    'poses': {'bottom': <String, Object?>{}, 'top': <String, Object?>{}},
  },
  kits: {
    'barbell': {'pieces': <Object?>[]},
  },
);

void main() {
  group('with Firestore (fake)', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreExerciseRepository repository;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      repository = FirestoreExerciseRepository(
        FirestoreExerciseSource(firestore),
      );
      await firestore.doc('animationKits/main').set({'kits': kitsText});
    });

    Future<void> storeRecipe(Object? recipe) => firestore
        .doc('exercises/ex_a/animation/main')
        .set({'recipe': recipe, 'contentHash': 'hash'});

    test('decodes the recipe and the kits', () async {
      await storeRecipe(recipeText);

      final result = await repository.getAnimation('ex_a');

      expect(result.valueOrNull, animation);
    });

    test('is null for an exercise without an animation', () async {
      final result = await repository.getAnimation('ex_a');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isNull);
    });

    test('fails on a recipe that is not a JSON object', () async {
      await storeRecipe('[1, 2');

      final result = await repository.getAnimation('ex_a');

      expect(result.failureOrNull, isA<UnknownFailure>());
    });

    test('fails on a recipe that is not text', () async {
      await storeRecipe({'keys': <Object?>[]});

      final result = await repository.getAnimation('ex_a');

      expect(result.failureOrNull, isA<UnknownFailure>());
    });

    test('fails when the kits are missing', () async {
      await storeRecipe(recipeText);
      await firestore.doc('animationKits/main').delete();

      final result = await repository.getAnimation('ex_a');

      expect(result.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('cache then server', () {
    late MockSource source;
    late FirestoreExerciseRepository repository;
    final notCached = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
    );

    setUp(() {
      source = MockSource();
      repository = FirestoreExerciseRepository(source);
      when(() => source.animationKits(any()))
          .thenAnswer((_) async => {'kits': kitsText});
    });

    setUpAll(() => registerFallbackValue(Source.cache));

    test('reads the server when the cache never loaded it', () async {
      when(() => source.animation('ex_a', Source.cache)).thenThrow(notCached);
      when(() => source.animation('ex_a', Source.server))
          .thenAnswer((_) async => {'recipe': recipeText});

      final result = await repository.getAnimation('ex_a');

      expect(result.valueOrNull, animation);
    });

    test('answers from the cache and refreshes it from the server', () async {
      when(() => source.animation('ex_a', Source.cache))
          .thenAnswer((_) async => {'recipe': recipeText});
      when(() => source.animation('ex_a', Source.server))
          .thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'x'));

      final result = await repository.getAnimation('ex_a');
      await pumpEventQueue();

      expect(result.valueOrNull, animation);
      verify(() => source.animation('ex_a', Source.server)).called(1);
    });

    test('answers a cached absence without waiting for the server', () async {
      when(() => source.animation('ex_a', Source.cache))
          .thenAnswer((_) async => null);
      when(() => source.animation('ex_a', Source.server))
          .thenAnswer((_) async => null);

      final result = await repository.getAnimation('ex_a');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isNull);
    });

    test('is a network failure offline with nothing cached', () async {
      when(() => source.animation('ex_a', Source.cache)).thenThrow(notCached);
      when(() => source.animation('ex_a', Source.server)).thenThrow(notCached);

      final result = await repository.getAnimation('ex_a');

      expect(result.failureOrNull, isA<NetworkFailure>());
    });
  });
}
