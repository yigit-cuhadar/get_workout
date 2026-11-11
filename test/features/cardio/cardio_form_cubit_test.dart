import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/cardio/domain/cardio_repository.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/cardio/domain/cardio_usecases.dart';
import 'package:get_workout/features/cardio/domain/cardio_validation.dart';
import 'package:get_workout/features/cardio/presentation/cardio_form_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockCardioRepository extends Mock implements CardioRepository {}

void main() {
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  const other = AuthUser(id: 'u2', email: 'c@d.co');
  final now = DateTime(2026, 11, 11, 12, 34, 56);
  final stored = CardioSession(
    id: 's1',
    type: CardioType.treadmillRun,
    date: DateTime(2026, 11, 10, 7, 30),
    duration: const Duration(hours: 1, minutes: 2, seconds: 3),
    distanceKm: 10,
    calories: 600,
    avgHeartRate: 150,
    incline: 1.5,
    note: 'Steady',
  );
  final unknown = CardioSession(
    id: 's2',
    type: CardioType.other,
    typeCode: 'unicycle',
    date: DateTime(2026, 11, 9, 8),
    duration: const Duration(minutes: 10),
    distanceKm: 3.2,
    calories: 100,
  );

  late MockAuthRepository auth;
  late MockCardioRepository cardio;
  late StreamController<AuthUser?> users;

  setUpAll(() {
    registerFallbackValue(stored);
    registerFallbackValue(<CardioField>{});
  });

  setUp(() {
    auth = MockAuthRepository();
    cardio = MockCardioRepository();
    users = StreamController<AuthUser?>.broadcast();
    when(() => auth.currentUser).thenReturn(member);
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => cardio.saveSession(any(), any(), fields: any(named: 'fields')))
        .thenAnswer((_) async => const Ok(null));
    when(() => cardio.deleteSession(any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  CardioFormCubit build({
    CardioSession? initial,
    DistanceUnit unit = DistanceUnit.km,
  }) => CardioFormCubit(
    saveSession: SaveCardioSession(cardio, clock: () => now),
    deleteSession: DeleteCardioSession(cardio),
    getCurrentUser: GetCurrentUser(auth),
    watchAuthUser: WatchAuthUser(auth),
    unit: unit,
    initial: initial,
    clock: () => now,
  );

  /// The one save's session and fields.
  (CardioSession, Set<CardioField>) saved() {
    final captured = verify(
      () => cardio.saveSession(
        'u1',
        captureAny(),
        fields: captureAny(named: 'fields'),
      ),
    ).captured;
    return (captured.first as CardioSession, captured.last as Set<CardioField>);
  }

  void neverSaved() => verifyNever(
    () => cardio.saveSession(any(), any(), fields: any(named: 'fields')),
  );

  group('initial state', () {
    test('a new session starts now, to the minute, with empty fields', () {
      final cubit = build();
      expect(cubit.isEditing, isFalse);
      expect(
        cubit.state,
        CardioFormState(
          type: CardioType.outdoorRun,
          date: DateTime(2026, 11, 11, 12, 34),
        ),
      );
    });

    test('an edit shows the stored values, distance in km', () {
      final state = build(initial: stored).state;
      expect(state.type, CardioType.treadmillRun);
      expect((state.hours, state.minutes, state.seconds), ('1', '2', '3'));
      expect(state.distance, '10');
      expect(state.calories, '600');
      expect(state.heartRate, '150');
      expect(state.incline, '1.5');
      expect(state.note, 'Steady');
    });

    test('an edit shows the distance in miles for an imperial user', () {
      expect(
        build(initial: stored, unit: DistanceUnit.mile).state.distance,
        '6.21',
      );
    });

    test('an unknown stored type shows as other', () {
      expect(build(initial: unknown).state.type, CardioType.other);
    });
  });

  group('validation', () {
    blocTest<CardioFormCubit, CardioFormState>(
      'shows every issue and saves nothing while the form is invalid',
      build: build,
      act: (cubit) => (cubit..setHeartRate('20')).save(),
      skip: 1,
      expect: () => [
        isA<CardioFormState>()
            .having((s) => s.status, 'status', CardioFormStatus.editing)
            .having((s) => s.issues, 'issues', {
              CardioIssue.durationMissing,
              CardioIssue.heartRateOutOfRange,
            }),
      ],
      verify: (_) => neverSaved(),
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'issues stay up to date after a failed attempt',
      build: build,
      act: (cubit) async {
        await cubit.save();
        cubit.setDuration(minutes: '20');
      },
      verify: (cubit) => expect(cubit.state.issues, isEmpty),
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'issues are not shown before the first save',
      build: build,
      act: (cubit) => cubit.setHeartRate('20'),
      verify: (cubit) => expect(cubit.state.issues, isEmpty),
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'unreadable numbers are issues of their field',
      build: build,
      act: (cubit) =>
          (cubit
                ..setDuration(minutes: '30')
                ..setDistance('5..2')
                ..setCalories('1.5'))
              .save(),
      verify: (cubit) {
        expect(cubit.state.issues, {
          CardioIssue.distanceOutOfRange,
          CardioIssue.caloriesOutOfRange,
        });
        neverSaved();
      },
    );

    for (final (text, issues) in [
      ('NaN', {CardioIssue.distanceOutOfRange, CardioIssue.inclineOutOfRange}),
      (
        'Infinity',
        {CardioIssue.distanceOutOfRange, CardioIssue.inclineOutOfRange},
      ),
      (
        '-Infinity',
        {CardioIssue.distanceOutOfRange, CardioIssue.inclineOutOfRange},
      ),
      (
        '1e400',
        {CardioIssue.distanceOutOfRange, CardioIssue.inclineOutOfRange},
      ),
      // Readable, but far below the minimum distance; a fine incline.
      ('1e-300', {CardioIssue.distanceOutOfRange}),
    ]) {
      blocTest<CardioFormCubit, CardioFormState>(
        '"$text" is never saved as a distance or incline',
        build: build,
        act: (cubit) =>
            (cubit
                  ..setType(CardioType.treadmillRun)
                  ..setDuration(minutes: '30')
                  ..setDistance(text)
                  ..setIncline(text))
                .save(),
        verify: (cubit) {
          expect(cubit.state.issues, issues);
          neverSaved();
        },
      );
    }

    blocTest<CardioFormCubit, CardioFormState>(
      'huge digit strings are issues, not numbers',
      build: build,
      act: (cubit) =>
          (cubit
                ..setDuration(minutes: '30')
                ..setCalories('9' * 40)
                ..setHeartRate('1' * 25))
              .save(),
      verify: (cubit) => expect(cubit.state.issues, {
        CardioIssue.caloriesOutOfRange,
        CardioIssue.heartRateOutOfRange,
      }),
    );

    for (final (name, hours, minutes, seconds) in [
      ('a digit string too long to read', '9' * 30, '', ''),
      ('more minutes than a day holds', '', '99999', ''),
      ('24 hours and a second', '24', '0', '1'),
    ]) {
      blocTest<CardioFormCubit, CardioFormState>(
        'a duration of $name is too long, not zero',
        build: build,
        act: (cubit) =>
            (cubit..setDuration(
                  hours: hours,
                  minutes: minutes,
                  seconds: seconds,
                ))
                .save(),
        verify: (cubit) {
          expect(cubit.state.issues, {CardioIssue.durationTooLong});
          neverSaved();
        },
      );
    }

    blocTest<CardioFormCubit, CardioFormState>(
      'a note longer than 500 characters is an issue',
      build: build,
      act: (cubit) =>
          (cubit
                ..setDuration(minutes: '30')
                ..setNote('x' * 501))
              .save(),
      verify: (cubit) => expect(cubit.state.issues, {CardioIssue.noteTooLong}),
    );
  });

  group('save', () {
    blocTest<CardioFormCubit, CardioFormState>(
      'a valid new session is saved for the current user',
      build: build,
      act: (cubit) =>
          (cubit
                ..setType(CardioType.treadmillWalk)
                ..setDuration(hours: '1', minutes: '5', seconds: '30')
                ..setDistance('4,5')
                ..setCalories(' 300 ')
                ..setHeartRate('')
                ..setIncline('-2')
                ..setNote('  Hills  '))
              .save(),
      verify: (cubit) {
        expect(cubit.state.status, CardioFormStatus.saved);
        expect(
          saved().$1,
          CardioSession(
            type: CardioType.treadmillWalk,
            date: DateTime(2026, 11, 11, 12, 34),
            duration: const Duration(hours: 1, minutes: 5, seconds: 30),
            distanceKm: 4.5,
            calories: 300,
            incline: -2,
            note: 'Hills',
          ),
        );
      },
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'emits saving, then saved',
      build: build,
      seed: () => CardioFormState(
        type: CardioType.hiit,
        date: DateTime(2026, 11, 11),
        minutes: '20',
      ),
      act: (cubit) => cubit.save(),
      expect: () => [
        isA<CardioFormState>().having(
          (s) => s.status,
          'status',
          CardioFormStatus.saving,
        ),
        isA<CardioFormState>().having(
          (s) => s.status,
          'status',
          CardioFormStatus.saved,
        ),
      ],
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'a distance typed in miles is stored in km',
      build: () => build(unit: DistanceUnit.mile),
      act: (cubit) =>
          (cubit
                ..setDuration(minutes: '30')
                ..setDistance('3'))
              .save(),
      verify: (_) => expect(saved().$1.distanceKm, closeTo(4.828032, 1e-9)),
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'an unedited distance in miles keeps the exact stored km',
      build: () => build(initial: stored, unit: DistanceUnit.mile),
      act: (cubit) => (cubit..setNote('Changed')).save(),
      verify: (_) {
        final session = saved().$1;
        expect(session.id, 's1');
        expect(session.distanceKm, 10);
        expect(session.note, 'Changed');
      },
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'an edit writes the fields the form shows; cleared ones are null',
      build: () => build(initial: stored),
      act: (cubit) => (cubit..setIncline('')).save(),
      verify: (_) {
        final (session, fields) = saved();
        expect(fields, {...CardioField.values});
        expect(session.incline, isNull);
        expect(session.distanceKm, 10);
      },
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'a type change drops what the new type does not use',
      build: () => build(initial: stored),
      act: (cubit) => (cubit..setType(CardioType.elliptical)).save(),
      verify: (_) {
        final (session, fields) = saved();
        expect(session.typeCode, 'elliptical');
        expect(session.distanceKm, isNull);
        expect(session.incline, isNull);
        expect(session.calories, 600);
        // Named, so the stored distance and incline are removed.
        expect(
          fields,
          containsAll([CardioField.distanceKm, CardioField.incline]),
        );
      },
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'an edit of an unknown type keeps its code and the fields it hides',
      build: () => build(initial: unknown),
      act: (cubit) =>
          (cubit
                ..setType(CardioType.other)
                ..setCalories('120'))
              .save(),
      verify: (_) {
        final (session, fields) = saved();
        expect(session.typeCode, 'unicycle');
        expect(session.calories, 120);
        expect(fields, {
          CardioField.calories,
          CardioField.avgHeartRate,
          CardioField.note,
        });
      },
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'picking a new type replaces an unknown one',
      build: () => build(initial: unknown),
      act: (cubit) => (cubit..setType(CardioType.outdoorCycle)).save(),
      verify: (_) {
        final (session, fields) = saved();
        expect(session.typeCode, 'outdoor_cycle');
        expect(fields, contains(CardioField.distanceKm));
      },
    );

    const failure = NetworkFailure();

    blocTest<CardioFormCubit, CardioFormState>(
      'a failed save keeps the inputs and reports the failure',
      setUp: () => when(
        () => cardio.saveSession(any(), any(), fields: any(named: 'fields')),
      ).thenAnswer((_) async => const Err(failure)),
      build: () => build(initial: stored),
      act: (cubit) => cubit.save(),
      verify: (cubit) {
        expect(cubit.state.status, CardioFormStatus.saveFailed);
        expect(cubit.state.failure, failure);
        expect(cubit.state.distance, '10');
      },
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'editing after a failure clears it',
      setUp: () => when(
        () => cardio.saveSession(any(), any(), fields: any(named: 'fields')),
      ).thenAnswer((_) async => const Err(failure)),
      build: () => build(initial: stored),
      act: (cubit) async {
        await cubit.save();
        cubit.setNote('x');
      },
      verify: (cubit) {
        expect(cubit.state.status, CardioFormStatus.editing);
        expect(cubit.state.failure, isNull);
      },
    );
  });

  group('user change', () {
    blocTest<CardioFormCubit, CardioFormState>(
      'the same user signing in again keeps the form open',
      build: () => build(initial: stored),
      act: (_) => users.add(member),
      expect: () => const <CardioFormState>[],
    );

    blocTest<CardioFormCubit, CardioFormState>(
      "another user closes the form, and it ignores input after that",
      build: () => build(initial: stored),
      act: (cubit) async {
        users.add(other);
        await pumpEventQueue();
        cubit.setNote('typed late');
        await cubit.save();
        await cubit.delete();
      },
      expect: () => [
        isA<CardioFormState>().having(
          (s) => s.status,
          'status',
          CardioFormStatus.closed,
        ),
      ],
      verify: (_) {
        neverSaved();
        verifyNever(() => cardio.deleteSession(any(), any()));
      },
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'signing out closes a new-session form too',
      build: build,
      act: (_) => users.add(null),
      expect: () => [
        isA<CardioFormState>().having(
          (s) => s.status,
          'status',
          CardioFormStatus.closed,
        ),
      ],
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'a user change not yet announced still blocks the save',
      build: () => build(initial: stored),
      act: (cubit) {
        when(() => auth.currentUser).thenReturn(other);
        return cubit.save();
      },
      verify: (cubit) {
        expect(cubit.state.status, CardioFormStatus.closed);
        neverSaved();
      },
    );
  });

  group('delete', () {
    blocTest<CardioFormCubit, CardioFormState>(
      'deletes the stored session',
      build: () => build(initial: stored),
      act: (cubit) => cubit.delete(),
      verify: (cubit) {
        expect(cubit.state.status, CardioFormStatus.deleted);
        verify(() => cardio.deleteSession('u1', 's1')).called(1);
      },
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'a failed delete reports the failure',
      setUp: () =>
          when(() => cardio.deleteSession(any(), any()))
              .thenAnswer((_) async => const Err(PermissionFailure())),
      build: () => build(initial: stored),
      act: (cubit) => cubit.delete(),
      verify: (cubit) =>
          expect(cubit.state.status, CardioFormStatus.deleteFailed),
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'a new session has nothing to delete',
      build: build,
      act: (cubit) => cubit.delete(),
      expect: () => const <CardioFormState>[],
      verify: (_) => verifyNever(() => cardio.deleteSession(any(), any())),
    );
  });
}
