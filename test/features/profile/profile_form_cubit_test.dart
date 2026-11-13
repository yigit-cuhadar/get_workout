import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_form_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:mocktail/mocktail.dart';

class MockProfileRepository extends Mock implements ProfileRepository {}

class MockUserLibraryRepository extends Mock implements UserLibraryRepository {}

void main() {
  late MockProfileRepository profiles;
  late MockUserLibraryRepository library;

  setUpAll(() {
    registerFallbackValue(const UserProfile());
    registerFallbackValue(<ProfileField>{});
    registerFallbackValue(<Equipment>{});
  });

  setUp(() {
    profiles = MockProfileRepository();
    library = MockUserLibraryRepository();
    when(() => library.saveEquipment(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => profiles.completeOnboarding(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => profiles.saveFields(any(), any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  ProfileFormCubit onboarding([UserProfile initial = const UserProfile()]) =>
      ProfileFormCubit.onboarding(
        uid: 'u1',
        initial: initial,
        completeOnboarding: CompleteOnboarding(
          profiles,
          SaveOwnedEquipment(library),
        ),
        now: () => DateTime(2026, 11, 11),
      );

  ProfileFormCubit edit(ProfileField field, UserProfile initial) =>
      ProfileFormCubit.edit(
        field: field,
        initial: initial,
        now: () => DateTime(2026, 11, 11),
      );

  const complete = UserProfile(
    goal: Goal.buildMuscle,
    level: Level.beginner,
    daysPerWeek: 3,
    equipment: {Equipment.dumbbell},
    sex: Sex.male,
    birthYear: 1990,
    heightCm: 180,
    weightKg: 80,
    targetWeightKg: 75,
  );

  /// Starts [cubit] and moves it forward to [field].
  Future<void> goTo(ProfileFormCubit cubit, ProfileField field) async {
    cubit.start();
    while (cubit.state.question != field) {
      await cubit.next();
    }
  }

  group('onboarding', () {
    test('opens with the welcome, which only moves on', () async {
      final cubit = onboarding(complete);
      expect(cubit.state.welcome, isTrue);
      expect(cubit.state.canContinue, isTrue);

      await cubit.next();
      cubit.back();
      expect(cubit.state.welcome, isTrue);

      cubit.start();
      expect(cubit.state.welcome, isFalse);
      expect(cubit.state.question, ProfileField.goal);
    });

    test('asks all nine questions in order, then saves', () async {
      final cubit = onboarding(complete)..start();
      final asked = <ProfileField>[];
      while (cubit.state.status == ProfileFormStatus.editing) {
        asked.add(cubit.state.question);
        await cubit.next();
      }
      expect(asked, ProfileField.values);
      verify(() => profiles.completeOnboarding('u1', complete)).called(1);
    });

    test('starts from the answers already stored', () {
      const stored = UserProfile(equipment: {Equipment.kettlebell});
      expect(onboarding(stored).state.answers, stored);
    });

    test('every choice question needs an answer to continue', () async {
      final cubit = onboarding()..start();
      for (final field in [
        ProfileField.goal,
        ProfileField.level,
        ProfileField.daysPerWeek,
        ProfileField.equipment,
        ProfileField.sex,
      ]) {
        expect(cubit.state.question, field);
        expect(cubit.state.canContinue, isFalse);
        await cubit.next();
        expect(cubit.state.question, field);
        switch (field) {
          case ProfileField.goal:
            cubit.setGoal(Goal.loseFat);
          case ProfileField.level:
            cubit.setLevel(Level.beginner);
          case ProfileField.daysPerWeek:
            cubit.setDaysPerWeek(3);
          case ProfileField.equipment:
            cubit.applyPreset(EquipmentProfile.homeGym);
          default:
            cubit.setSex(Sex.female);
        }
        expect(cubit.state.canContinue, isTrue);
        await cubit.next();
      }
      expect(cubit.state.question, ProfileField.birthYear);
    });

    test('a number question shows answered with where its input starts, '
        'the target at the body weight', () async {
      final cubit = onboarding(
        const UserProfile(
          goal: Goal.loseFat,
          level: Level.beginner,
          daysPerWeek: 3,
          equipment: {},
          sex: Sex.female,
        ),
      );

      await goTo(cubit, ProfileField.birthYear);
      expect(cubit.state.answers.birthYear, 1996);
      expect(cubit.state.canContinue, isTrue);

      await cubit.next();
      expect(cubit.state.answers.heightCm, 170);
      await cubit.next();
      expect(cubit.state.answers.weightKg, 70);
      cubit.setWeight(82.5, WeightUnit.kg);
      await cubit.next();
      expect(cubit.state.answers.targetWeightKg, 82.5);
    });

    test(
      'a target weight follows the body weight until the user sets it',
      () async {
        final cubit = onboarding(
          complete
              .without(ProfileField.weight)
              .without(ProfileField.targetWeight),
        );
        await goTo(cubit, ProfileField.targetWeight);
        expect(cubit.state.answers.targetWeightKg, 70);

        cubit.back();
        cubit.setWeight(90, WeightUnit.kg);
        await cubit.next();
        expect(cubit.state.answers.targetWeightKg, 90);

        cubit.setTargetWeight(85, WeightUnit.kg);
        cubit.back();
        cubit.setWeight(95, WeightUnit.kg);
        await cubit.next();
        expect(cubit.state.answers.targetWeightKg, 85);
      },
    );

    test('a stored target weight is the user\'s own', () async {
      final cubit = onboarding(complete.without(ProfileField.weight));
      await goTo(cubit, ProfileField.targetWeight);
      expect(cubit.state.answers.targetWeightKg, 75);
    });

    test('a stored number answer is kept', () async {
      final cubit = onboarding(complete);
      await goTo(cubit, ProfileField.targetWeight);
      expect(cubit.state.answers, complete);
    });

    test('back returns to the previous question and keeps answers', () async {
      final cubit = onboarding()
        ..start()
        ..setGoal(Goal.loseFat);
      await cubit.next();
      cubit.setLevel(Level.beginner);

      cubit.back();
      expect(cubit.state.step, 0);
      expect(cubit.state.welcome, isFalse);
      expect(
        cubit.state.answers,
        const UserProfile(goal: Goal.loseFat, level: Level.beginner),
      );
    });

    blocTest<ProfileFormCubit, ProfileFormState>(
      'next on the last question completes onboarding with the answers',
      build: () => onboarding(complete),
      act: (cubit) async {
        await goTo(cubit, ProfileField.targetWeight);
        await cubit.next();
      },
      skip: 9,
      expect: () => [
        isA<ProfileFormState>().having(
          (state) => state.status,
          'status',
          ProfileFormStatus.submitted,
        ),
      ],
      verify: (_) =>
          verify(() => profiles.completeOnboarding('u1', complete)).called(1),
    );

    test('nothing is stored before the last question', () async {
      final cubit = onboarding(complete);
      await goTo(cubit, ProfileField.targetWeight);
      verifyNever(() => profiles.completeOnboarding(any(), any()));
      verifyNever(() => library.saveEquipment(any(), any()));
    });

    test('the equipment is saved through the library', () async {
      final cubit = onboarding(complete);
      await goTo(cubit, ProfileField.targetWeight);
      await cubit.next();

      verify(() => library.saveEquipment('u1', {Equipment.dumbbell})).called(1);
    });

    test('a failed equipment save fails the completion', () async {
      when(() => library.saveEquipment(any(), any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      final cubit = onboarding(complete);
      await goTo(cubit, ProfileField.targetWeight);

      await cubit.next();

      expect(cubit.state.status, ProfileFormStatus.editing);
      expect(cubit.state.failure, isA<NetworkFailure>());
    });

    test('a failed completion reports it and allows another try', () async {
      when(() => profiles.completeOnboarding(any(), any()))
          .thenAnswer((_) async => const Err(PermissionFailure()));
      final cubit = onboarding(complete);
      await goTo(cubit, ProfileField.targetWeight);

      await cubit.next();

      expect(cubit.state.status, ProfileFormStatus.editing);
      expect(cubit.state.failure, isA<PermissionFailure>());
      await cubit.next();
      verify(() => profiles.completeOnboarding(any(), any())).called(2);
    });

    test('nothing moves while saving', () async {
      final saving = Completer<Result<void>>();
      when(() => profiles.completeOnboarding(any(), any()))
          .thenAnswer((_) => saving.future);
      final cubit = onboarding(complete);
      await goTo(cubit, ProfileField.targetWeight);

      final finishing = cubit.next();
      cubit.back();
      await cubit.next();

      expect(cubit.state.question, ProfileField.targetWeight);
      saving.complete(const Ok(null));
      await finishing;
      verify(() => profiles.completeOnboarding(any(), any())).called(1);
    });

    test('clear does nothing in onboarding', () async {
      final cubit = onboarding(complete);
      await goTo(cubit, ProfileField.sex);
      expect(cubit.state.canClear, isFalse);

      await cubit.clear();

      expect(cubit.state.answers, complete);
      expect(cubit.state.status, ProfileFormStatus.editing);
    });
  });

  group('answers', () {
    test('days per week outside 2 to 6 are ignored', () {
      final cubit = onboarding()
        ..setDaysPerWeek(7)
        ..setDaysPerWeek(1);
      expect(cubit.state.answers.daysPerWeek, isNull);
      cubit.setDaysPerWeek(3);
      expect(cubit.state.answers.daysPerWeek, 3);
    });

    test('a preset fills the equipment, which can then be tuned', () {
      final cubit = onboarding()..applyPreset(EquipmentProfile.dumbbells);
      expect(cubit.state.answers.equipment, {
        Equipment.dumbbell,
        Equipment.bench,
      });

      cubit
        ..toggleEquipment(Equipment.box)
        ..toggleEquipment(Equipment.dumbbell);
      expect(cubit.state.answers.equipment, {Equipment.bench, Equipment.box});
    });

    test('bodyweight is an answer: no equipment at all', () {
      final cubit = edit(ProfileField.equipment, const UserProfile());
      expect(cubit.state.canContinue, isFalse);
      cubit
        ..applyPreset(EquipmentProfile.bodyweight)
        ..toggleEquipment(Equipment.pullUpBar)
        ..toggleEquipment(Equipment.dipStation);
      expect(cubit.state.answers.equipment, isEmpty);
      expect(cubit.state.canContinue, isTrue);
    });

    test('a birth year gives an age of 13 to 100', () {
      final cubit = onboarding()..setBirthYear(2014);
      expect(cubit.state.answers.birthYear, isNull);
      cubit.setBirthYear(1925);
      expect(cubit.state.answers.birthYear, isNull);

      cubit.setBirthYear(2013);
      expect(cubit.state.answers.birthYear, 2013);
      expect(cubit.birthYearRange, (min: 1926, max: 2013));
    });

    test('a stored birth year outside the range stays selectable', () async {
      // Plausible when given, too young by this year's range.
      final cubit = edit(
        ProfileField.birthYear,
        const UserProfile(birthYear: 2015),
      );
      expect(cubit.birthYearRange, (min: 1926, max: 2015));
      expect(cubit.state.answers.birthYear, 2015);

      cubit
        ..setBirthYear(2013)
        ..setBirthYear(2015);
      expect(cubit.state.answers.birthYear, 2015);
      cubit.setBirthYear(2014);
      expect(cubit.state.answers.birthYear, 2015);
    });

    test('heights and weights are converted to metric', () {
      final cubit = onboarding()
        ..setHeight(70, LengthUnit.inch)
        ..setWeight(176.5, WeightUnit.lb)
        ..setTargetWeight(165, WeightUnit.lb);

      expect(cubit.state.answers.heightCm, closeTo(177.8, 1e-9));
      expect(cubit.state.answers.weightKg, closeTo(80.059, 1e-3));
      expect(cubit.state.answers.targetWeightKg, closeTo(74.843, 1e-3));
    });

    test('the limits apply to the metric value; a value outside them is '
        'refused and changes nothing', () {
      // 39 in is 99.06 cm, 40 in is 101.6 cm.
      final cubit = onboarding();
      expect(cubit.setHeight(39, LengthUnit.inch), isFalse);
      expect(cubit.state.answers.heightCm, isNull);
      expect(cubit.setHeight(40, LengthUnit.inch), isTrue);

      // 66 lb is 29.9 kg, 67 lb is 30.4 kg.
      expect(cubit.setWeight(66, WeightUnit.lb), isFalse);
      expect(cubit.setWeight(67, WeightUnit.lb), isTrue);
      expect(cubit.setTargetWeight(301, WeightUnit.kg), isFalse);
      expect(cubit.state.answers.targetWeightKg, isNull);

      cubit.setHeight(300, LengthUnit.cm);
      expect(cubit.state.answers.heightCm, closeTo(101.6, 1e-9));
    });

    test('a typed entry is accepted only as a plain number in range', () {
      final cubit = onboarding();
      expect(cubit.enterWeight('176,5', WeightUnit.lb), isTrue);
      expect(cubit.state.answers.weightKg, closeTo(80.059, 1e-3));
      expect(cubit.enterHeight(' 180 ', LengthUnit.cm), isTrue);
      expect(cubit.state.answers.heightCm, 180);
      expect(cubit.enterTargetWeight('75', WeightUnit.kg), isTrue);

      expect(cubit.enterTargetWeight('500', WeightUnit.kg), isFalse);
      expect(cubit.enterTargetWeight('', WeightUnit.kg), isFalse);
      expect(cubit.state.answers.targetWeightKg, 75);
    });

    test('non-finite and absurd entries are refused, never exceptions', () {
      const entries = [
        'Infinity',
        '-Infinity',
        'NaN',
        '1e400',
        '-1e400',
        '1e7',
        '99999999999999999999999999',
        '12abc',
        '..',
      ];
      final cubit = onboarding();
      for (final text in entries) {
        expect(cubit.enterHeight(text, LengthUnit.inch), isFalse, reason: text);
        expect(cubit.enterWeight(text, WeightUnit.lb), isFalse, reason: text);
        expect(
          cubit.enterTargetWeight(text, WeightUnit.kg),
          isFalse,
          reason: text,
        );
        expect(cubit.state.answers, const UserProfile(), reason: text);
      }
    });
  });

  group('editing', () {
    const stored = UserProfile(goal: Goal.loseFat, targetWeightKg: 70);

    test('asks only its question and submits without writing', () async {
      final cubit = edit(ProfileField.goal, stored)..setGoal(Goal.buildMuscle);
      expect(cubit.state.questions, [ProfileField.goal]);
      expect(cubit.state.welcome, isFalse);

      await cubit.next();

      expect(cubit.state.status, ProfileFormStatus.submitted);
      expect(
        cubit.state.answers,
        const UserProfile(goal: Goal.buildMuscle, targetWeightKg: 70),
      );
      verifyZeroInteractions(profiles);
      verifyZeroInteractions(library);
    });

    test('an unanswered number question starts where its input does', () {
      expect(edit(ProfileField.height, stored).state.answers.heightCm, 170);
      expect(
        edit(ProfileField.targetWeight, stored).state.answers.targetWeightKg,
        70,
      );
    });

    test('a stored personal answer can be cleared, which submits it', () async {
      final cubit = edit(ProfileField.height, stored.copyWith(heightCm: 182));
      expect(cubit.state.answers.heightCm, 182);
      expect(cubit.state.canClear, isTrue);

      await cubit.clear();

      expect(cubit.state.status, ProfileFormStatus.submitted);
      expect(cubit.state.answers, stored);
    });

    test('a training answer cannot be cleared', () async {
      final cubit = edit(ProfileField.goal, stored);
      expect(cubit.state.canClear, isFalse);

      await cubit.clear();

      expect(cubit.state.status, ProfileFormStatus.editing);
      expect(cubit.state.answers, stored);
    });

    test('an unanswered personal question needs an answer to save', () async {
      final cubit = edit(ProfileField.sex, const UserProfile());
      expect(cubit.state.canContinue, isFalse);
      await cubit.next();
      expect(cubit.state.status, ProfileFormStatus.editing);
    });
  });
}
