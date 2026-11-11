import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/cardio/data/firestore_cardio_repository.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreCardioRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreCardioRepository(firestore);
  });

  CollectionReference<Map<String, dynamic>> cardio(String uid) =>
      firestore.collection('users/$uid/cardio');

  final run = CardioSession(
    type: CardioType.treadmillRun,
    date: DateTime(2026, 11, 10, 7, 30),
    duration: const Duration(minutes: 32, seconds: 5),
    distanceKm: 5.5,
    calories: 380,
    avgHeartRate: 152,
    incline: 1.5,
    note: 'Easy',
  );

  Future<List<CardioSession>> sessions(String uid) =>
      repository.watchSessions(uid).first;

  test('a new session gets an id and is stored with its codes', () async {
    expect((await repository.saveSession('u1', run)).isOk, isTrue);

    final docs = (await cardio('u1').get()).docs;
    expect(docs, hasLength(1));
    expect(docs.single.data(), {
      'type': 'treadmill_run',
      'date': Timestamp.fromDate(run.date),
      'durationS': 1925,
      'distanceKm': 5.5,
      'calories': 380,
      'avgHeartRate': 152,
      'incline': 1.5,
      'note': 'Easy',
    });
    expect(await sessions('u1'), [run.withId(docs.single.id)]);
  });

  test('missing optional fields are left out', () async {
    final hiit = CardioSession(
      type: CardioType.hiit,
      date: DateTime(2026, 11, 9, 18),
      duration: const Duration(minutes: 20),
    );

    await repository.saveSession('u1', hiit);

    final data = (await cardio('u1').get()).docs.single.data();
    expect(data.keys, unorderedEquals(['type', 'date', 'durationS']));
  });

  test('sessions come newest first', () async {
    for (final day in [3, 9, 6]) {
      await repository.saveSession(
        'u1',
        CardioSession(
          type: CardioType.outdoorWalk,
          date: DateTime(2026, 11, day),
          duration: const Duration(minutes: 10),
        ),
      );
    }

    expect((await sessions('u1')).map((s) => s.date.day), [9, 6, 3]);
  });

  test("a user never sees another user's sessions", () async {
    await repository.saveSession('u1', run);

    expect(await sessions('u2'), isEmpty);
    expect(await sessions('u1'), hasLength(1));
  });

  test('saving a stored session replaces it', () async {
    await repository.saveSession('u1', run);
    final stored = (await sessions('u1')).single;
    final edited = CardioSession(
      id: stored.id,
      type: CardioType.outdoorRun,
      date: stored.date,
      duration: const Duration(minutes: 40),
      distanceKm: 6,
    );

    await repository.saveSession('u1', edited);

    expect(await sessions('u1'), [edited]);
    // Fields the edit dropped are gone from the document.
    final data = (await cardio('u1').doc(stored.id).get()).data()!;
    expect(data.containsKey('incline'), isFalse);
    expect(data.containsKey('note'), isFalse);
  });

  test('delete removes only that session', () async {
    await repository.saveSession('u1', run);
    await repository.saveSession(
      'u1',
      CardioSession(
        type: CardioType.rowing,
        date: DateTime(2026, 11, 1),
        duration: const Duration(minutes: 15),
      ),
    );
    final rowing = (await sessions('u1')).last;

    expect((await repository.deleteSession('u1', rowing.id!)).isOk, isTrue);

    expect((await sessions('u1')).map((s) => s.type), [
      CardioType.treadmillRun,
    ]);
  });

  test('an unknown stored type reads as other', () async {
    await cardio('u1').doc('x').set({
      'type': 'unicycle',
      'date': Timestamp.fromDate(DateTime(2026, 11, 1)),
      'durationS': 600,
    });

    final session = (await sessions('u1')).single;
    expect(session.type, CardioType.other);
    expect(session.duration, const Duration(minutes: 10));
  });

  test('the stream emits every change', () async {
    final emitted = repository.watchSessions('u1').map((s) => s.length);
    final expectation = expectLater(emitted, emitsInOrder([0, 1]));

    await repository.saveSession('u1', run);

    await expectation;
  });
}
