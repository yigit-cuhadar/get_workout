import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/data/firestore_body_repository.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreBodyRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreBodyRepository(firestore);
  });

  DocumentReference<Map<String, dynamic>> doc(String id) =>
      firestore.doc('users/u1/bodyEntries/$id');

  final day = BodyEntry(
    id: 'e1',
    date: DateTime(2026, 11, 10, 8),
    weightKg: 81.4,
    measurements: const {
      BodyMeasurement.waist: 86,
      BodyMeasurement.leftCalf: 38.5,
    },
    photos: const {PhotoPose.front: 'users/u1/photos/e1/front.jpg'},
  );

  Future<void> settle() => pumpEventQueue();

  test('a quick weight log stores only its date and weight', () async {
    final log = BodyEntry(id: 'w1', date: DateTime(2026, 11, 9), weightKg: 80);

    expect((await repository.addEntry('u1', log)).isOk, isTrue);
    await settle();

    expect((await doc('w1').get()).data(), {
      'date': Timestamp.fromDate(DateTime(2026, 11, 9)),
      'weightKg': 80,
    });
  });

  test('a measurement day stores its maps by code and reads back', () async {
    await repository.addEntry('u1', day);
    await settle();

    expect((await doc('e1').get()).data(), {
      'date': Timestamp.fromDate(day.date),
      'weightKg': 81.4,
      'measurements': {'waist': 86, 'leftCalf': 38.5},
      'photos': {'front': 'users/u1/photos/e1/front.jpg'},
    });
    expect(await repository.watchEntries('u1').first, [day]);
  });

  test('entries arrive newest first; unreadable ones are skipped', () async {
    await repository.addEntry('u1', day);
    await repository.addEntry(
      'u1',
      BodyEntry(id: 'w1', date: DateTime(2026, 11, 11), weightKg: 80),
    );
    await doc('bad').set({'weightKg': 70});
    await settle();

    final entries = await repository.watchEntries('u1').first;
    expect(entries.map((entry) => entry.id), ['w1', 'e1']);
    expect(await repository.watchEntries('u2').first, isEmpty);
  });

  test('values of the wrong type and unknown keys are left out', () async {
    await doc('x').set({
      'date': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'weightKg': 'heavy',
      'measurements': {'waist': 80, 'wingspan': 190, 'hips': 'wide'},
      'photos': {'front': 'p', 'top': 'q', 'back': 3},
    });

    final entry = (await repository.watchEntries('u1').first).single;
    expect(entry.weightKg, isNull);
    expect(entry.measurements, {BodyMeasurement.waist: 80});
    expect(entry.photos, {PhotoPose.front: 'p'});
  });

  test('an update replaces known fields and keeps unknown keys', () async {
    await doc('e1').set({
      'date': Timestamp.fromDate(day.date),
      'weightKg': 81.4,
      'measurements': {'waist': 86, 'neck': 38, 'wingspan': 190},
      'photos': {'front': 'f', 'top': 't'},
    });

    final edited = BodyEntry(
      id: 'e1',
      date: day.date,
      measurements: const {BodyMeasurement.waist: 85},
      photos: const {PhotoPose.back: 'b'},
    );
    expect((await repository.updateEntry('u1', edited)).isOk, isTrue);
    await settle();

    expect((await doc('e1').get()).data(), {
      'date': Timestamp.fromDate(day.date),
      'measurements': {'waist': 85, 'wingspan': 190},
      'photos': {'back': 'b', 'top': 't'},
    });
  });

  test('a delete removes the document', () async {
    await repository.addEntry('u1', day);
    await settle();

    expect((await repository.deleteEntry('u1', 'e1')).isOk, isTrue);
    await settle();

    expect((await doc('e1').get()).exists, isFalse);
  });

  test('new ids are unique', () {
    expect(repository.newEntryId('u1'), isNot(repository.newEntryId('u1')));
  });
}
