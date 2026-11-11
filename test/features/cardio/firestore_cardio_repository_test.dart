import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/cardio/data/firestore_cardio_repository.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';

void main() {
  const allFields = {...CardioField.values};
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

  Future<void> save(CardioSession session, [Set<CardioField>? fields]) async {
    final result = await repository.saveSession(
      'u1',
      session,
      fields: fields ?? allFields,
    );
    expect(result.isOk, isTrue);
    await pumpEventQueue();
  }

  test('a new session gets an id and is stored with its codes', () async {
    await save(run);

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
    await save(
      CardioSession(
        type: CardioType.hiit,
        date: DateTime(2026, 11, 9, 18),
        duration: const Duration(minutes: 20),
      ),
    );

    final data = (await cardio('u1').get()).docs.single.data();
    expect(data.keys, unorderedEquals(['type', 'date', 'durationS']));
  });

  test('sessions come newest first', () async {
    for (final day in [3, 9, 6]) {
      await save(
        CardioSession(
          type: CardioType.outdoorWalk,
          date: DateTime(2026, 11, day),
          duration: const Duration(minutes: 10),
        ),
      );
    }

    expect((await sessions('u1')).map((s) => s.date.day), [9, 6, 3]);
  });

  test('the list holds the most recent 500 sessions', () async {
    final start = DateTime(2025);
    for (var i = 0; i < 501; i++) {
      await cardio('u1').add({
        'type': 'hiit',
        'date': Timestamp.fromDate(start.add(Duration(hours: i))),
        'durationS': 600,
      });
    }

    final list = await sessions('u1');
    expect(list, hasLength(FirestoreCardioRepository.maxSessions));
    expect(list.last.date, start.add(const Duration(hours: 1)));
  });

  test("a user never sees another user's sessions", () async {
    await save(run);

    expect(await sessions('u2'), isEmpty);
    expect(await sessions('u1'), hasLength(1));
  });

  test('an edit writes the given fields, removing the empty ones', () async {
    await save(run);
    final stored = (await sessions('u1')).single;
    final edited = CardioSession(
      id: stored.id,
      type: CardioType.outdoorRun,
      date: stored.date,
      duration: const Duration(minutes: 40),
      distanceKm: 6,
    );

    await save(edited, allFields);

    expect(await sessions('u1'), [edited]);
    final data = (await cardio('u1').doc(stored.id).get()).data()!;
    expect(data.containsKey('incline'), isFalse);
    expect(data.containsKey('note'), isFalse);
  });

  test('an edit keeps an unknown type, fields it does not write and fields '
      'the app does not know', () async {
    await cardio('u1').doc('x').set({
      'type': 'unicycle',
      'date': Timestamp.fromDate(DateTime(2026, 11, 1, 8)),
      'durationS': 600,
      'distanceKm': 3.2,
      'calories': 100,
      'gear': 'one wheel',
    });
    final stored = (await sessions('u1')).single;
    expect(stored.type, CardioType.other);
    expect(stored.typeCode, 'unicycle');

    // "Other" shows no distance, so the form does not write it.
    await save(
      CardioSession(
        id: 'x',
        type: CardioType.other,
        typeCode: stored.typeCode,
        date: stored.date,
        duration: const Duration(minutes: 15),
        calories: 150,
      ),
      {CardioField.calories, CardioField.avgHeartRate, CardioField.note},
    );

    expect((await cardio('u1').doc('x').get()).data(), {
      'type': 'unicycle',
      'date': Timestamp.fromDate(DateTime(2026, 11, 1, 8)),
      'durationS': 900,
      'distanceKm': 3.2,
      'calories': 150,
      'gear': 'one wheel',
    });
  });

  test('delete removes only that session', () async {
    await save(run);
    await save(
      CardioSession(
        type: CardioType.rowing,
        date: DateTime(2026, 11, 1),
        duration: const Duration(minutes: 15),
      ),
    );
    final rowing = (await sessions('u1')).last;

    expect((await repository.deleteSession('u1', rowing.id!)).isOk, isTrue);
    await pumpEventQueue();

    expect((await sessions('u1')).map((s) => s.type), [
      CardioType.treadmillRun,
    ]);
  });

  test('unreadable documents are skipped, the rest still listed', () async {
    final date = Timestamp.fromDate(DateTime(2026, 11, 1));
    final docs = <String, Map<String, Object?>>{
      'good': {'type': 'hiit', 'date': date, 'durationS': 600},
      'noType': {'date': date, 'durationS': 600},
      'numericType': {'type': 3, 'date': date, 'durationS': 600},
      'noDuration': {'type': 'hiit', 'date': date},
      'textDuration': {'type': 'hiit', 'date': date, 'durationS': '600'},
      'zeroDuration': {'type': 'hiit', 'date': date, 'durationS': 0},
      'hugeDuration': {'type': 'hiit', 'date': date, 'durationS': 1e300},
      'oddOptional': {
        'type': 'outdoor_run',
        'date': date,
        'durationS': 600,
        'distanceKm': 'far',
        'calories': 1e300,
        'note': 42,
      },
    };
    for (final MapEntry(:key, :value) in docs.entries) {
      await cardio('u1').doc(key).set(value);
    }

    final list = await sessions('u1');

    expect(list.map((s) => s.id), unorderedEquals(['good', 'oddOptional']));
    // The fake cannot order mixed types, so this one is read directly.
    expect(
      FirestoreCardioRepository.fromMap('stringDate', {
        'type': 'hiit',
        'date': '2026-11-01',
        'durationS': 600,
      }),
      isNull,
    );
    final odd = list.firstWhere((s) => s.id == 'oddOptional');
    expect(odd.distanceKm, isNull);
    expect(odd.calories, isNull);
    expect(odd.note, isNull);
  });

  test('a write the server rejects later is reported once', () async {
    final rejected = <Failure>[];
    repository.rejectedWrites.listen(rejected.add);

    // The update of a document that is gone fails after it started.
    final result = await repository.saveSession(
      'u1',
      run.withId('gone'),
      fields: allFields,
    );
    await pumpEventQueue();

    expect(result.isOk, isTrue);
    expect(rejected, [isA<NotFoundFailure>()]);
  });

  test('the stream emits every change', () async {
    final emitted = repository.watchSessions('u1').map((s) => s.length);
    final expectation = expectLater(emitted, emitsInOrder([0, 1]));

    await save(run);

    await expectation;
  });
}
