import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/data/firestore_custom_exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreCustomExerciseRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreCustomExerciseRepository(firestore);
  });

  CollectionReference<Map<String, dynamic>> stored(String uid) =>
      firestore.collection('users/$uid/customExercises');

  const press = CustomExercise(
    name: 'Landmine Press',
    loggingType: LoggingType.weightReps,
    mainMuscles: [Muscle.frontDelt],
    secondaryMuscles: [Muscle.triceps, Muscle.oblique],
    equipment: [Equipment.landmine, Equipment.barbell],
    note: 'Half kneeling',
  );

  Future<List<CustomExercise>> listOf(String uid) =>
      repository.watchCustomExercises(uid).first;

  Future<String> create(CustomExercise exercise, {String uid = 'u1'}) async {
    expect((await repository.createCustomExercise(uid, exercise)).isOk, isTrue);
    await pumpEventQueue();
    return (await stored(uid).get()).docs.last.id;
  }

  CustomExercise withId(CustomExercise exercise, String id) => CustomExercise(
    id: id,
    name: exercise.name,
    loggingType: exercise.loggingType,
    mainMuscles: exercise.mainMuscles,
    secondaryMuscles: exercise.secondaryMuscles,
    equipment: exercise.equipment,
    note: exercise.note,
  );

  test('a new one gets a custom_ id and is stored with its codes', () async {
    final id = await create(press);

    expect(id, matches(RegExp(r'^custom_[A-Za-z0-9]{20}$')));
    expect((await stored('u1').doc(id).get()).data(), {
      'name': 'Landmine Press',
      'loggingType': 'weight_reps',
      'mainMuscles': ['front_delt'],
      'secondaryMuscles': ['triceps', 'oblique'],
      'equipment': ['landmine', 'barbell'],
      'note': 'Half kneeling',
    });
    expect(await listOf('u1'), [withId(press, id)]);
  });

  test('a missing note is left out', () async {
    final id = await create(
      const CustomExercise(name: 'Plank', mainMuscles: [Muscle.abdominal]),
    );
    final data = (await stored('u1').doc(id).get()).data()!;
    expect(data.containsKey('note'), isFalse);
    expect(data['equipment'], isEmpty);
  });

  test("a user never sees another user's", () async {
    await create(press, uid: 'u2');
    expect(await listOf('u1'), isEmpty);
  });

  test('an edit replaces the fields, removes a cleared note and keeps '
      'fields it does not know', () async {
    final id = await create(press);
    await stored('u1').doc(id).update({'videoUrl': 'later'});

    final edited = CustomExercise(
      id: id,
      name: 'Kneeling Landmine Press',
      loggingType: LoggingType.reps,
      mainMuscles: const [Muscle.midDelt],
    );
    expect((await repository.updateCustomExercise('u1', edited)).isOk, isTrue);
    await pumpEventQueue();

    expect((await stored('u1').doc(id).get()).data(), {
      'name': 'Kneeling Landmine Press',
      'loggingType': 'reps',
      'mainMuscles': ['mid_delt'],
      'secondaryMuscles': <String>[],
      'equipment': <String>[],
      'videoUrl': 'later',
    });
  });

  test('delete removes it and its favourite, and nothing else', () async {
    final id = await create(press);
    final other = await create(press);
    await firestore.doc('users/u1').set({
      'favoriteExerciseIds': [id, 'ex_squat'],
      'profile': {'goal': 'get_stronger'},
    });

    expect((await repository.deleteCustomExercise('u1', id)).isOk, isTrue);
    await pumpEventQueue();

    expect(await listOf('u1'), [withId(press, other)]);
    expect((await firestore.doc('users/u1').get()).data(), {
      'favoriteExerciseIds': ['ex_squat'],
      'profile': {'goal': 'get_stronger'},
    });
  });

  test('counts what is stored', () async {
    Future<int?> count() async =>
        (await repository.countCustomExercises('u1')).valueOrNull;
    expect(await count(), 0);
    await create(press);
    await create(press);
    expect(await count(), 2);
  });

  test('unreadable documents are skipped, unknown codes dropped', () async {
    await stored('u1').doc('custom_nameless').set({
      'loggingType': 'reps',
      'mainMuscles': ['pec'],
    });
    await stored('u1').doc('custom_newtype').set({
      'name': 'Future',
      'loggingType': 'distance',
      'mainMuscles': ['pec'],
    });
    await stored('u1').doc('custom_newmuscle').set({
      'name': 'Neck Curl',
      'loggingType': 'reps',
      'mainMuscles': ['neck'],
    });
    await stored('u1').doc('custom_ok').set({
      'name': 'Odd',
      'loggingType': 'reps',
      'mainMuscles': ['pec', 'neck'],
      'secondaryMuscles': 'pec',
      'equipment': ['bench', 'hover_board'],
      'note': 7,
    });

    expect(await listOf('u1'), [
      const CustomExercise(
        id: 'custom_ok',
        name: 'Odd',
        loggingType: LoggingType.reps,
        mainMuscles: [Muscle.pec],
        equipment: [Equipment.bench],
      ),
    ]);
  });

  test('a write the server rejects later is reported once', () async {
    final rejected = <Failure>[];
    repository.rejectedWrites.listen(rejected.add);

    // The update of a document that is gone fails after it started.
    final result = await repository.updateCustomExercise(
      'u1',
      withId(press, 'custom_gone'),
    );
    await pumpEventQueue();

    expect(result.isOk, isTrue);
    expect(rejected, [isA<NotFoundFailure>()]);
  });
}
