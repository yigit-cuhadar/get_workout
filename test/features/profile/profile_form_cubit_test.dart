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

  /// Moves [cubit] forward to [field], or to the summary when null.
  Future<void> goTo(ProfileFormCubit cubit, ProfileField? field) async {
    while (cubit.state.question != field) {
      await cubit.next();
    }
  }

  group('onboarding', () {
    test('asks all nine questions in order, then a summary', () async {
      final cubit = onboarding(complete);
      final asked = <ProfileField?>[];
      while (cubit.state.question != null) {
        asked.add(cubit.state.question);
        await cubit.next();
      }
      expect(asked, ProfileField.values);
      expect(cubit.state.step, 9);
      expect(cubit.state.status, ProfileFormStatus.editing);
    });

    test('starts from the answers already stored', () {
      const stored = UserProfile(equipment: {Equipment.kettlebell});
      expect(onboarding(stored).state.answers, stored);
    });

    test('an unanswered question cannot be passed', () async {
      final cubit = onboarding();
      expect(cubit.state.canContinue, isFalse);

      await cubit.next();
      expect(cubit.state.step, 0);

      cubit.setGoal(Goal.buildMuscle);
      expect(cubit.state.canContinue, isTrue);
      await cubit.next();
      expect(cubit.state.step, 1);
    });

    test('a personal question needs an answer or a skip', () async {
      final cubit = onboarding(complete.without(ProfileField.sex));
      await goTo(cubit, ProfileField.sex);
      expect(cubit.state.canContinue, isFalse);
      expect(cubit.state.canSkipQuestion, isTrue);

      cubit.skipQuestion();
      expect(cubit.state.question, ProfileField.birthYear);
      expect(cubit.state.answers.sex, isNull);
    });

    test('skipping a question drops its entry, valid or not', () async {
      final cubit = onboarding(complete);
      await goTo(cubit, ProfileField.weight);
      cubit
        ..enterWeight('2000', WeightUnit.kg)
        ..skipQuestion();
      expect(cubit.state.question, ProfileField.targetWeight);
      expect(cubit.state.invalid, isEmpty);
      expect(cubit.state.answers.weightKg, isNull);

      cubit.skipQuestion();
      expect(cubit.state.question, isNull);
      expect(cubit.state.answers.targetWeightKg, isNull);
    });

    test('the training questions cannot be skipped one by one', () async {
      final cubit = onboarding();
      for (final field in [
        ProfileField.goal,
        ProfileField.level,
        ProfileField.daysPerWeek,
        ProfileField.equipment,
      ]) {
        expect(cubit.state.question, field);
        expect(cubit.state.canSkipQuestion, isFalse);
        cubit.skipQuestion();
        expect(cubit.state.question, field);
        switch (field) {
          case ProfileField.goal:
            cubit.setGoal(Goal.loseFat);
          case ProfileField.level:
            cubit.setLevel(Level.beginner);
          case ProfileField.daysPerWeek:
            cubit.setDaysPerWeek(3);
          default:
            cubit.applyPreset(EquipmentProfile.homeGym);
        }
        await cubit.next();
      }
      expect(cubit.state.question, ProfileField.sex);
    });

    test('a birth year is a plausibility check, not an age gate', () async {
      // An implausible year blocks only its own answer; skipping it moves on.
      final cubit = onboarding(complete.without(ProfileField.birthYear));
      await goTo(cubit, ProfileField.birthYear);
      cubit.enterBirthYear('2020');
      expect(cubit.state.canContinue, isFalse);

      cubit.skipQuestion();
      expect(cubit.state.question, ProfileField.height);
    });

    test('back returns to the previous question and keeps answers', () async {
      final cubit = onboarding()..setGoal(Goal.loseFat);
      await cubit.next();
      cubit.setLevel(Level.beginner);

      cubit.back();
      expect(cubit.state.step, 0);
      cubit.back();
      expect(cubit.state.step, 0);
      expect(
        cubit.state.answers,
        const UserProfile(goal: Goal.loseFat, level: Level.beginner),
      );
    });

    blocTest<ProfileFormCubit, ProfileFormState>(
      'finishing on the summary completes onboarding with the answers',
      build: () => onboarding(complete),
      act: (cubit) async {
        await goTo(cubit, null);
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

    test('the equipment is saved through the library', () async {
      final cubit = onboarding()..applyPreset(EquipmentProfile.dumbbells);

      await cubit.skip();

      const owned = {Equipment.dumbbell, Equipment.bench};
      verify(() => library.saveEquipment('u1', owned)).called(1);
      verify(
        () => profiles.completeOnboarding(
          'u1',
          const UserProfile(equipment: owned),
        ),
      ).called(1);
    });

    test('without an equipment answer the library is not written', () async {
      await onboarding().skip();
      verifyNever(() => library.saveEquipment(any(), any()));
    });

    test('a failed equipment save fails the completion', () async {
      when(() => library.saveEquipment(any(), any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      final cubit = onboarding()..applyPreset(EquipmentProfile.bodyweight);

      await cubit.skip();

      expect(cubit.state.status, ProfileFormStatus.editing);
      expect(cubit.state.failure, isA<NetworkFailure>());
    });

    test('skipping completes onboarding with what was answered', () async {
      final cubit = onboarding()..setGoal(Goal.loseFat);
      await cubit.next();
      cubit.setLevel(Level.advanced);

      await cubit.skip();

      expect(cubit.state.status, ProfileFormStatus.submitted);
      verify(
        () => profiles.completeOnboarding(
          'u1',
          const UserProfile(goal: Goal.loseFat, level: Level.advanced),
        ),
      ).called(1);
    });

    test('skipping leaves out an invalid entry', () async {
      final cubit = onboarding()..enterHeight('20', LengthUnit.cm);

      await cubit.skip();

      verify(() => profiles.completeOnboarding('u1', const UserProfile()))
          .called(1);
    });

    test('a failed completion reports it and allows another try', () async {
      when(() => profiles.completeOnboarding(any(), any()))
          .thenAnswer((_) async => const Err(PermissionFailure()));
      final cubit = onboarding();

      await cubit.skip();

      expect(cubit.state.status, ProfileFormStatus.editing);
      expect(cubit.state.failure, isA<PermissionFailure>());
      await cubit.skip();
      verify(() => profiles.completeOnboarding(any(), any())).called(2);
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
      final cubit = onboarding()..enterBirthYear('2014');
      expect(cubit.state.invalid, {ProfileField.birthYear});
      expect(cubit.state.answers.birthYear, isNull);

      cubit.enterBirthYear('2013');
      expect(cubit.state.invalid, isEmpty);
      expect(cubit.state.answers.birthYear, 2013);

      cubit.enterBirthYear('1990.5');
      expect(cubit.state.invalid, {ProfileField.birthYear});
      expect(cubit.birthYearRange, (min: 1926, max: 2013));
    });

    test('non-finite and absurd entries are invalid, never exceptions', () {
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
        cubit
          ..enterBirthYear(text)
          ..enterHeight(text, LengthUnit.inch)
          ..enterWeight(text, WeightUnit.lb)
          ..enterTargetWeight(text, WeightUnit.kg);
        expect(cubit.state.invalid, {
          ProfileField.birthYear,
          ProfileField.height,
          ProfileField.weight,
          ProfileField.targetWeight,
        }, reason: text);
        expect(cubit.state.answers, const UserProfile(), reason: text);
      }
    });

    test('an invalid entry blocks its question', () async {
      final cubit = onboarding(complete);
      await goTo(cubit, ProfileField.weight);

      cubit.enterWeight('heavy', WeightUnit.kg);

      expect(cubit.state.invalid, {ProfileField.weight});
      expect(cubit.state.canContinue, isFalse);
    });

    test('clearing an entry unanswers it', () {
      final cubit = onboarding()..enterTargetWeight('70', WeightUnit.kg);
      expect(cubit.state.answers.targetWeightKg, 70);

      cubit.enterTargetWeight(' ', WeightUnit.kg);
      expect(cubit.state.answers.targetWeightKg, isNull);
      expect(cubit.state.invalid, isEmpty);
    });

    test('heights and weights are converted to metric at entry', () {
      final cubit = onboarding()
        ..enterHeight('70', LengthUnit.inch)
        ..enterWeight('176,5', WeightUnit.lb)
        ..enterTargetWeight('165', WeightUnit.lb);

      expect(cubit.state.answers.heightCm, closeTo(177.8, 1e-9));
      expect(cubit.state.answers.weightKg, closeTo(80.059, 1e-3));
      expect(cubit.state.answers.targetWeightKg, closeTo(74.843, 1e-3));
    });

    test('the limits apply to the metric value', () {
      // 39 in is 99.06 cm, 40 in is 101.6 cm.
      final cubit = onboarding()..enterHeight('39', LengthUnit.inch);
      expect(cubit.state.invalid, {ProfileField.height});
      cubit.enterHeight('40', LengthUnit.inch);
      expect(cubit.state.invalid, isEmpty);

      // 66 lb is 29.9 kg, 67 lb is 30.4 kg.
      cubit.enterWeight('66', WeightUnit.lb);
      expect(cubit.state.invalid, {ProfileField.weight});
      cubit.enterWeight('67', WeightUnit.lb);
      expect(cubit.state.invalid, isEmpty);
    });

    test('a unit change drops an invalid entry and keeps an answer', () {
      final cubit = onboarding()
        ..enterHeight('180', LengthUnit.cm)
        ..enterWeight('3', WeightUnit.kg);

      cubit
        ..unitChanged(ProfileField.height)
        ..unitChanged(ProfileField.weight);

      expect(cubit.state.invalid, isEmpty);
      expect(cubit.state.answers.heightCm, 180);
    });
  });

  group('editing', () {
    const stored = UserProfile(goal: Goal.loseFat, targetWeightKg: 70);

    test('asks only its question and submits without writing', () async {
      final cubit = edit(ProfileField.goal, stored)..setGoal(Goal.buildMuscle);
      expect(cubit.state.questions, [ProfileField.goal]);

      await cubit.next();

      expect(cubit.state.status, ProfileFormStatus.submitted);
      expect(
        cubit.state.answers,
        const UserProfile(goal: Goal.buildMuscle, targetWeightKg: 70),
      );
      verifyZeroInteractions(profiles);
      verifyZeroInteractions(library);
    });

    test('an emptied target weight is submitted as unanswered', () async {
      final cubit = edit(ProfileField.targetWeight, stored)
        ..enterTargetWeight('', WeightUnit.kg);

      await cubit.next();

      expect(cubit.state.status, ProfileFormStatus.submitted);
      expect(cubit.state.answers, const UserProfile(goal: Goal.loseFat));
    });

    test('an invalid entry is not submitted', () async {
      final cubit = edit(ProfileField.targetWeight, stored)
        ..enterTargetWeight('500', WeightUnit.kg);

      await cubit.next();

      expect(cubit.state.status, ProfileFormStatus.editing);
    });

    test('a personal answer may be cleared', () {
      final cubit = edit(ProfileField.sex, const UserProfile());
      expect(cubit.state.canContinue, isTrue);
      expect(cubit.state.canSkipQuestion, isFalse);
      expect(
        edit(ProfileField.goal, const UserProfile()).state.canContinue,
        isFalse,
      );
    });

    test('skip does nothing outside onboarding', () async {
      final cubit = edit(ProfileField.goal, stored);
      await cubit.skip();
      expect(cubit.state.status, ProfileFormStatus.editing);
    });
  });
}
