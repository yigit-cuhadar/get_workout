import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/programs/data/firestore_program_repository.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';

import 'fixtures.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreProgramRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreProgramRepository(firestore);
  });

  CollectionReference<Map<String, dynamic>> programs(String uid) =>
      firestore.collection('users/$uid/programs');
  DocumentReference<Map<String, dynamic>> user(String uid) =>
      firestore.collection('users').doc(uid);

  final started = DateTime(2026, 11, 11, 18, 30);
  final active = ActiveProgram(
    programId: 'p1',
    weekdays: const [1, 3, 5],
    nextDayIndex: 1,
    nextDate: CalendarDate(2026, 11, 13),
    startedAt: started,
  );

  Future<String> create(Program program, [String uid = 'u1']) async {
    final result = await repository.createProgram(uid, program);
    await pumpEventQueue();
    return result.valueOrNull!;
  }

  group('programs', () {
    test('a new program is stored with its fields and read back', () async {
      final id = await create(
        program(lengthWeeks: 8).copyWith(
          days: [
            ProgramDay(
              name: 'Full body',
              items: [
                item('a', targetKg: 60, group: 'A'),
                item(
                  'plank',
                  repMin: null,
                  repMax: null,
                  durationS: 45,
                  group: 'A',
                ),
              ],
            ),
          ],
        ),
      );

      final data = (await programs('u1').doc(id).get()).data()!;
      expect(data['name'], 'Upper Lower');
      expect(data['origin'], 'own');
      expect(data['lengthWeeks'], 8);
      expect(data.containsKey('sourceId'), isFalse);
      expect(data['updatedAt'], isA<Timestamp>());
      expect(data['days'], [
        {
          'name': 'Full body',
          'items': [
            {
              'exerciseId': 'a',
              'sets': 3,
              'repMin': 8,
              'repMax': 12,
              'restS': 90,
              'targetKg': 60.0,
              'group': 'A',
            },
            {
              'exerciseId': 'plank',
              'sets': 3,
              'durationS': 45,
              'restS': 90,
              'group': 'A',
            },
          ],
        },
      ]);
      final read = (await repository.getProgram('u1', id)).valueOrNull!;
      expect(read.id, id);
      expect(read.lengthWeeks, 8);
      expect(read.days.single.items.last.durationS, 45);
    });

    test('the list comes sorted by name, case aside', () async {
      for (final name in ['push', 'Arms', 'legs']) {
        await create(program(name: name));
      }
      final list = await repository.watchPrograms('u1').first;
      expect([for (final p in list) p.name], ['Arms', 'legs', 'push']);
    });

    test('users only see their own programs', () async {
      await create(program(name: 'Mine'), 'u1');
      await create(program(name: 'Theirs'), 'u2');
      final list = await repository.watchPrograms('u1').first;
      expect([for (final p in list) p.name], ['Mine']);
      final id = (await programs('u2').get()).docs.single.id;
      expect(
        (await repository.getProgram('u1', id)).failureOrNull,
        isA<NotFoundFailure>(),
      );
    });

    test(
      'unreadable documents are skipped, odd values read leniently',
      () async {
        await programs('u1').doc('noName').set({'days': []});
        await programs('u1').doc('noDays').set({'name': 'X', 'days': 'many'});
        await programs('u1').doc('odd').set({
          'name': 'Odd',
          'origin': 'from_the_future',
          'sourceId': 7,
          'lengthWeeks': 'eight',
          'days': [
            'not a day',
            {
              'name': 5,
              'items': [
                {'sets': 3},
                'not an item',
                {
                  'exerciseId': 'a',
                  'sets': '3',
                  'repMin': 8.4,
                  'repMax': 1e12,
                  'restS': 'long',
                  'targetKg': 'heavy',
                  'group': '',
                },
              ],
            },
            {'name': 'Empty'},
          ],
        });

        final list = await repository.watchPrograms('u1').first;
        expect(list, hasLength(1));
        final odd = list.single;
        expect(odd.origin, ProgramOrigin.own);
        expect(odd.sourceId, isNull);
        expect(odd.lengthWeeks, isNull);
        expect(odd.days, [
          const ProgramDay(
            items: [ProgramItem(exerciseId: 'a', sets: 0, repMin: 8, restS: 0)],
          ),
          const ProgramDay(name: 'Empty'),
        ]);
        expect(
          (await repository.getProgram('u1', 'noName')).failureOrNull,
          isA<NotFoundFailure>(),
        );
      },
    );

    test(
      'an edit keeps unknown fields of the program, days and items',
      () async {
        await programs('u1').doc('p1').set({
          'name': 'Old',
          'origin': 'catalog',
          'sourceId': 'c9',
          'lengthWeeks': 6,
          'coverColor': 'teal',
          'days': [
            {
              'name': 'A',
              'focus': 'push',
              'items': [
                {
                  'exerciseId': 'a',
                  'sets': 3,
                  'repMin': 8,
                  'repMax': 12,
                  'restS': 90,
                  'tempo': '3-1-1',
                },
              ],
            },
          ],
        });

        final stored = (await repository.getProgram('u1', 'p1')).valueOrNull!;
        final day = stored.days.single;
        await repository.updateProgram(
          'u1',
          stored.copyWith(
            name: 'New',
            lengthWeeks: () => null,
            days: [
              day.copyWith(items: [day.items.single.copyWith(sets: 5)]),
            ],
          ),
        );
        await pumpEventQueue();

        final data = (await programs('u1').doc('p1').get()).data()!;
        expect(data['name'], 'New');
        expect(data.containsKey('lengthWeeks'), isFalse);
        expect(data['origin'], 'catalog');
        expect(data['sourceId'], 'c9');
        expect(data['coverColor'], 'teal');
        expect(data['updatedAt'], isA<Timestamp>());
        final storedDay = (data['days'] as List).single as Map;
        expect(storedDay['focus'], 'push');
        final storedItem = (storedDay['items'] as List).single as Map;
        expect(storedItem['tempo'], '3-1-1');
        expect(storedItem['sets'], 5);
      },
    );

    test(
      'deleting a program leaves the active one alone unless asked',
      () async {
        await user('u1').set({
          'activeProgram': {'programId': 'p2'},
        });
        await programs('u1').doc('p1').set({'name': 'X', 'days': []});

        await repository.deleteProgram('u1', 'p1', clearActive: false);
        await pumpEventQueue();

        expect((await programs('u1').doc('p1').get()).exists, isFalse);
        expect((await user('u1').get()).data(), {
          'activeProgram': {'programId': 'p2'},
        });
      },
    );

    test(
      'deleting the active program also stops it, keeping the rest',
      () async {
        await user('u1').set({
          'activeProgram': FirestoreProgramRepository.activeToMap(active),
          'settings': {'weightUnit': 'lb'},
          'favoriteExerciseIds': ['a'],
        });
        await programs('u1').doc('p1').set({'name': 'X', 'days': []});

        await repository.deleteProgram('u1', 'p1', clearActive: true);
        await pumpEventQueue();

        expect((await programs('u1').doc('p1').get()).exists, isFalse);
        expect((await user('u1').get()).data(), {
          'settings': {'weightUnit': 'lb'},
          'favoriteExerciseIds': ['a'],
        });
      },
    );
  });

  group('active program', () {
    Future<Map<String, dynamic>?> userData() async =>
        (await user('u1').get()).data();

    test('starting writes the active program next to other data', () async {
      await user('u1').set({
        'settings': {'weightUnit': 'lb'},
        'profile': {'goal': 'get_stronger'},
        'favoriteExerciseIds': ['a'],
      });

      await repository.startProgram('u1', active);
      await pumpEventQueue();

      expect(await userData(), {
        'settings': {'weightUnit': 'lb'},
        'profile': {'goal': 'get_stronger'},
        'favoriteExerciseIds': ['a'],
        'activeProgram': {
          'programId': 'p1',
          'weekdays': [1, 3, 5],
          'nextDayIndex': 1,
          'nextDate': '2026-11-13',
          'startedAt': Timestamp.fromDate(started),
        },
      });
      expect(await repository.watchActiveProgram('u1').first, active);
    });

    test('starting replaces a previous active program entirely', () async {
      await user('u1').set({
        'activeProgram': {
          ...FirestoreProgramRepository.activeToMap(active),
          'reminder': '07:00',
        },
      });

      final other = ActiveProgram(
        programId: 'p2',
        weekdays: const [2],
        nextDayIndex: 0,
        nextDate: CalendarDate(2026, 11, 17),
        startedAt: started,
      );
      await repository.startProgram('u1', other);
      await pumpEventQueue();

      expect(
        (await userData())!['activeProgram'],
        FirestoreProgramRepository.activeToMap(other),
      );
    });

    test('an update keeps unknown fields and other data', () async {
      await user('u1').set({
        'settings': {'weightUnit': 'kg'},
        'activeProgram': {
          ...FirestoreProgramRepository.activeToMap(active),
          'reminder': '07:00',
        },
      });

      await repository.updateActiveProgram(
        'u1',
        active.copyWith(weekdays: const [2, 4, 6], nextDayIndex: 2),
      );
      await pumpEventQueue();

      final data = (await userData())!;
      expect(data['settings'], {'weightUnit': 'kg'});
      expect(data['activeProgram'], {
        'programId': 'p1',
        'weekdays': [2, 4, 6],
        'nextDayIndex': 2,
        'nextDate': '2026-11-13',
        'startedAt': Timestamp.fromDate(started),
        'reminder': '07:00',
      });
    });

    test('stopping removes only the active program', () async {
      await user('u1').set({
        'settings': {'weightUnit': 'kg'},
        'activeProgram': FirestoreProgramRepository.activeToMap(active),
      });

      await repository.stopProgram('u1');
      await pumpEventQueue();

      expect(await userData(), {
        'settings': {'weightUnit': 'kg'},
      });
      expect(await repository.watchActiveProgram('u1').first, isNull);
    });

    test('is per user', () async {
      await repository.startProgram('u2', active);
      await pumpEventQueue();
      expect(await repository.watchActiveProgram('u1').first, isNull);
      expect(await repository.watchActiveProgram('u2').first, active);
    });

    test('an unreadable active program reads as none', () {
      final valid = FirestoreProgramRepository.activeToMap(active);
      for (final broken in [
        null,
        'p1',
        <String, Object?>{},
        {...valid, 'programId': ''},
        {...valid, 'weekdays': <int>[]},
        {
          ...valid,
          'weekdays': [0, 8, '3'],
        },
        {...valid, 'nextDate': '13.11.2026'},
        {...valid, 'startedAt': '2026-11-11'},
      ]) {
        expect(
          FirestoreProgramRepository.activeFromMap(broken),
          isNull,
          reason: '$broken',
        );
      }
    });

    test('odd weekdays and day index read leniently', () {
      final read = FirestoreProgramRepository.activeFromMap({
        ...FirestoreProgramRepository.activeToMap(active),
        'weekdays': [5, 9, 1, 5, 'x'],
        'nextDayIndex': -2,
      });
      expect(read, active.copyWith(weekdays: const [1, 5], nextDayIndex: 0));
    });
  });
}
