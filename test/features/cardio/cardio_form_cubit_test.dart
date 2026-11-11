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

  late MockAuthRepository auth;
  late MockCardioRepository cardio;

  setUpAll(() => registerFallbackValue(stored));

  setUp(() {
    auth = MockAuthRepository();
    cardio = MockCardioRepository();
    when(() => auth.currentUser).thenReturn(member);
    when(() => cardio.saveSession(any(), any()))
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
    unit: unit,
    initial: initial,
    clock: () => now,
  );

  CardioSession saved() =>
      verify(() => cardio.saveSession('u1', captureAny())).captured.single
          as CardioSession;

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
      final cubit = build(initial: stored);
      expect(cubit.isEditing, isTrue);
      expect(cubit.state.type, CardioType.treadmillRun);
      expect(cubit.state.duration, stored.duration);
      expect(cubit.state.distance, '10');
      expect(cubit.state.calories, '600');
      expect(cubit.state.heartRate, '150');
      expect(cubit.state.incline, '1.5');
      expect(cubit.state.note, 'Steady');
    });

    test('an edit shows the distance in miles for an imperial user', () {
      expect(
        build(initial: stored, unit: DistanceUnit.mile).state.distance,
        '6.21',
      );
    });
  });

  group('save', () {
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
      verify: (_) => verifyNever(() => cardio.saveSession(any(), any())),
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'issues stay up to date after a failed attempt',
      build: build,
      act: (cubit) async {
        await cubit.save();
        cubit.setDuration(const Duration(minutes: 20));
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
                ..setDuration(const Duration(minutes: 30))
                ..setDistance('5..2')
                ..setCalories('1.5'))
              .save(),
      verify: (cubit) => expect(cubit.state.issues, {
        CardioIssue.distanceOutOfRange,
        CardioIssue.caloriesOutOfRange,
      }),
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'a valid new session is saved for the current user',
      build: build,
      act: (cubit) =>
          (cubit
                ..setType(CardioType.treadmillWalk)
                ..setDuration(const Duration(minutes: 45))
                ..setDistance('4,5')
                ..setCalories(' 300 ')
                ..setHeartRate('')
                ..setIncline('-2')
                ..setNote('  Hills  '))
              .save(),
      verify: (cubit) {
        expect(cubit.state.status, CardioFormStatus.saved);
        expect(
          saved(),
          CardioSession(
            type: CardioType.treadmillWalk,
            date: DateTime(2026, 11, 11, 12, 34),
            duration: const Duration(minutes: 45),
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
        duration: const Duration(minutes: 20),
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
                ..setDuration(const Duration(minutes: 30))
                ..setDistance('3'))
              .save(),
      verify: (_) => expect(saved().distanceKm, closeTo(4.828032, 1e-9)),
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'an unedited distance in miles keeps the exact stored km',
      build: () => build(initial: stored, unit: DistanceUnit.mile),
      act: (cubit) => (cubit..setNote('Changed')).save(),
      verify: (_) {
        final session = saved();
        expect(session.id, 's1');
        expect(session.distanceKm, 10);
        expect(session.note, 'Changed');
      },
    );

    blocTest<CardioFormCubit, CardioFormState>(
      'fields the new type does not use are dropped',
      build: () => build(initial: stored),
      act: (cubit) => (cubit..setType(CardioType.elliptical)).save(),
      verify: (_) {
        final session = saved();
        expect(session.type, CardioType.elliptical);
        expect(session.distanceKm, isNull);
        expect(session.incline, isNull);
        expect(session.calories, 600);
        expect(session.avgHeartRate, 150);
      },
    );

    const failure = NetworkFailure();

    blocTest<CardioFormCubit, CardioFormState>(
      'a failed save keeps the inputs and reports the failure',
      setUp: () =>
          when(() => cardio.saveSession(any(), any()))
              .thenAnswer((_) async => const Err(failure)),
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
      setUp: () =>
          when(() => cardio.saveSession(any(), any()))
              .thenAnswer((_) async => const Err(failure)),
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

    blocTest<CardioFormCubit, CardioFormState>(
      'never saves for a user other than the one it was opened for',
      build: () => build(initial: stored),
      act: (cubit) {
        when(() => auth.currentUser)
            .thenReturn(const AuthUser(id: 'u2', email: 'c@d.co'));
        return cubit.save();
      },
      verify: (cubit) {
        expect(cubit.state.status, CardioFormStatus.saveFailed);
        verifyNever(() => cardio.saveSession(any(), any()));
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
