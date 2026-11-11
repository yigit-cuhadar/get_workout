import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/custom_exercise_form_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockCustomExerciseRepository extends Mock
    implements CustomExerciseRepository {}

void main() {
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  const other = AuthUser(id: 'u2', email: 'c@d.co');
  const stored = CustomExercise(
    id: 'custom_a',
    name: 'Landmine Press',
    loggingType: LoggingType.reps,
    mainMuscles: [Muscle.frontDelt],
    secondaryMuscles: [Muscle.triceps],
    equipment: [Equipment.landmine],
    note: 'Slow',
  );

  late MockAuthRepository auth;
  late MockCustomExerciseRepository repository;
  late StreamController<AuthUser?> users;

  setUpAll(() => registerFallbackValue(stored));

  setUp(() {
    auth = MockAuthRepository();
    repository = MockCustomExerciseRepository();
    users = StreamController<AuthUser?>.broadcast();
    when(() => auth.currentUser).thenReturn(member);
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(
      () => repository.countCustomExercises(any()),
    ).thenAnswer((_) async => const Ok(0));
    when(
      () => repository.createCustomExercise(any(), any()),
    ).thenAnswer((_) async => const Ok(null));
    when(
      () => repository.updateCustomExercise(any(), any()),
    ).thenAnswer((_) async => const Ok(null));
  });

  tearDown(() => users.close());

  CustomExerciseFormCubit build([CustomExercise? initial]) =>
      CustomExerciseFormCubit(
        saveExercise: SaveCustomExercise(repository),
        getCurrentUser: GetCurrentUser(auth),
        watchAuthUser: WatchAuthUser(auth),
        initial: initial,
      );

  test('a new one starts empty, logged with weight and reps', () {
    final cubit = build();
    expect(cubit.state, const CustomExerciseFormState());
    expect(cubit.state.loggingType, LoggingType.weightReps);
    expect(cubit.isEditing, isFalse);
  });

  test('an edit shows the stored values', () {
    final cubit = build(stored);
    expect(
      cubit.state,
      const CustomExerciseFormState(
        name: 'Landmine Press',
        loggingType: LoggingType.reps,
        mainMuscles: {Muscle.frontDelt},
        secondaryMuscles: {Muscle.triceps},
        equipment: {Equipment.landmine},
        note: 'Slow',
      ),
    );
    expect(cubit.isEditing, isTrue);
  });

  test('a muscle is main or secondary, never both', () {
    final cubit = build()
      ..toggleSecondaryMuscle(Muscle.pec)
      ..toggleMainMuscle(Muscle.pec);
    expect(cubit.state.mainMuscles, {Muscle.pec});
    expect(cubit.state.secondaryMuscles, isEmpty);
    cubit.toggleSecondaryMuscle(Muscle.pec);
    expect(cubit.state.mainMuscles, isEmpty);
    expect(cubit.state.secondaryMuscles, {Muscle.pec});
  });

  test('bodyweight replaces other equipment and is replaced by it', () {
    final cubit = build()
      ..toggleEquipment(Equipment.box)
      ..toggleEquipment(Equipment.bench)
      ..toggleEquipment(Equipment.bodyweight);
    expect(cubit.state.equipment, {Equipment.bodyweight});
    cubit.toggleEquipment(Equipment.box);
    expect(cubit.state.equipment, {Equipment.box});
    cubit.toggleEquipment(Equipment.box);
    expect(cubit.state.equipment, isEmpty);
  });

  blocTest<CustomExerciseFormCubit, CustomExerciseFormState>(
    'shows issues only once saving was tried, then keeps them current',
    build: build,
    act: (cubit) async {
      cubit.setName(' ');
      await cubit.save();
      cubit
        ..setName('Press')
        ..toggleMainMuscle(Muscle.pec);
    },
    expect: () => [
      const CustomExerciseFormState(name: ' '),
      const CustomExerciseFormState(
        name: ' ',
        issues: {
          CustomExerciseIssue.nameMissing,
          CustomExerciseIssue.mainMusclesMissing,
        },
      ),
      const CustomExerciseFormState(
        name: 'Press',
        issues: {CustomExerciseIssue.mainMusclesMissing},
      ),
      const CustomExerciseFormState(name: 'Press', mainMuscles: {Muscle.pec}),
    ],
    verify: (_) => verifyNever(
      () => repository.createCustomExercise(any(), any()),
    ),
  );

  blocTest<CustomExerciseFormCubit, CustomExerciseFormState>(
    'saves a new one, muscles and equipment in vocabulary order',
    build: build,
    act: (cubit) => (cubit
          ..setName(' Cossack Squat ')
          ..toggleMainMuscle(Muscle.quads)
          ..toggleMainMuscle(Muscle.adductor)
          ..toggleEquipment(Equipment.kettlebell)
          ..toggleEquipment(Equipment.plate))
        .save(),
    skip: 5,
    expect: () => [
      isA<CustomExerciseFormState>().having(
        (state) => state.status,
        'status',
        CustomExerciseFormStatus.saving,
      ),
      isA<CustomExerciseFormState>().having(
        (state) => state.status,
        'status',
        CustomExerciseFormStatus.saved,
      ),
    ],
    verify: (_) => verify(
      () => repository.createCustomExercise(
        'u1',
        const CustomExercise(
          name: 'Cossack Squat',
          mainMuscles: [Muscle.adductor, Muscle.quads],
          equipment: [Equipment.kettlebell, Equipment.plate],
        ),
      ),
    ).called(1),
  );

  blocTest<CustomExerciseFormCubit, CustomExerciseFormState>(
    'an edit updates the stored one',
    build: () => build(stored),
    act: (cubit) => (cubit..setNote('')).save(),
    verify: (cubit) {
      expect(cubit.state.status, CustomExerciseFormStatus.saved);
      verify(
        () => repository.updateCustomExercise(
          'u1',
          const CustomExercise(
            id: 'custom_a',
            name: 'Landmine Press',
            loggingType: LoggingType.reps,
            mainMuscles: [Muscle.frontDelt],
            secondaryMuscles: [Muscle.triceps],
            equipment: [Equipment.landmine],
          ),
        ),
      ).called(1);
    },
  );

  blocTest<CustomExerciseFormCubit, CustomExerciseFormState>(
    'reports the limit as the save failure',
    setUp: () => when(
      () => repository.countCustomExercises('u1'),
    ).thenAnswer((_) async => const Ok(CustomExerciseLimits.maxCount)),
    build: build,
    act: (cubit) => (cubit
          ..setName('Press')
          ..toggleMainMuscle(Muscle.pec))
        .save(),
    verify: (cubit) {
      expect(cubit.state.status, CustomExerciseFormStatus.saveFailed);
      expect(cubit.state.failure, CustomExerciseLimits.limitReached);
    },
  );

  blocTest<CustomExerciseFormCubit, CustomExerciseFormState>(
    'closes when the user changes, and then never writes',
    build: () => build(stored),
    act: (cubit) async {
      users.add(other);
      await pumpEventQueue();
      when(() => auth.currentUser).thenReturn(other);
      cubit.setName('Changed');
      await cubit.save();
    },
    expect: () => [
      isA<CustomExerciseFormState>().having(
        (state) => state.status,
        'status',
        CustomExerciseFormStatus.closed,
      ),
    ],
    verify: (_) => verifyNever(
      () => repository.updateCustomExercise(any(), any()),
    ),
  );
}
