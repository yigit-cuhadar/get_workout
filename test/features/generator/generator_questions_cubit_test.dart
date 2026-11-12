import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/generator/domain/generator_answers.dart';
import 'package:get_workout/features/generator/presentation/generator_questions_cubit.dart';

void main() {
  const none = (goal: null, level: null, daysPerWeek: null, equipment: null);

  GeneratorQuestionsCubit answeredUpTo(GeneratorStep step) {
    final cubit = GeneratorQuestionsCubit((
      goal: Goal.getStronger,
      level: Level.advanced,
      daysPerWeek: 4,
      equipment: EquipmentProfile.homeGym.equipment,
    ));
    while (cubit.state.step != step) {
      cubit.next();
    }
    return cubit;
  }

  test('prefills what the user already answered', () {
    final cubit = GeneratorQuestionsCubit((
      goal: Goal.loseFat,
      level: Level.beginner,
      daysPerWeek: 3,
      equipment: {Equipment.bodyweight, Equipment.dumbbell},
    ));
    expect(
      cubit.state,
      const GeneratorQuestionsState(
        goal: Goal.loseFat,
        level: Level.beginner,
        daysPerWeek: 3,
        equipment: {Equipment.dumbbell},
      ),
    );
    expect(cubit.state.sessionMinutes, 60);
  });

  test('leaves days the generator does not offer unanswered', () {
    for (final days in [1, 7]) {
      final cubit = GeneratorQuestionsCubit((
        goal: null,
        level: null,
        daysPerWeek: days,
        equipment: null,
      ));
      expect(cubit.state.daysPerWeek, isNull);
    }
  });

  test('moves on only once the question is answered', () {
    final cubit = GeneratorQuestionsCubit(none);
    cubit.next();
    expect(cubit.state.step, GeneratorStep.goal);
    cubit
      ..setGoal(Goal.buildMuscle)
      ..next();
    expect(cubit.state.step, GeneratorStep.level);
    cubit.next();
    expect(cubit.state.step, GeneratorStep.level);
    cubit
      ..setLevel(Level.intermediate)
      ..next()
      ..setDays(5)
      ..next();
    // A session length is preselected.
    expect(cubit.state.answered, isTrue);
    cubit.next();
    expect(cubit.state.step, GeneratorStep.equipment);
    expect(cubit.state.answered, isFalse);
    // Bodyweight only is an answer.
    cubit.toggleEquipment(Equipment.dumbbell);
    cubit.toggleEquipment(Equipment.dumbbell);
    expect(cubit.state.equipment, isEmpty);
    expect(cubit.state.answered, isTrue);
  });

  test('goes back, but not before the first question', () {
    final cubit = answeredUpTo(GeneratorStep.days);
    expect(cubit.back(), isTrue);
    expect(cubit.state.step, GeneratorStep.level);
    expect(cubit.back(), isTrue);
    expect(cubit.back(), isFalse);
    expect(cubit.state.step, GeneratorStep.goal);
  });

  test('the last question gives the answers', () {
    final cubit = answeredUpTo(GeneratorStep.split)
      ..setSessionMinutes(45)
      ..toggleFocus(Muscle.glute)
      ..exclude(['ex_a', 'ex_b'])
      ..include('ex_a')
      ..setEasyArea(EasyArea.knees)
      ..setSplit(TrainingSplit.upperLower);
    expect(cubit.state.isLast, isTrue);
    cubit.next();
    expect(cubit.state.step, GeneratorStep.split);
    expect(
      cubit.state.answers,
      GeneratorAnswers(
        goal: Goal.getStronger,
        level: Level.advanced,
        daysPerWeek: 4,
        sessionMinutes: 45,
        equipment: EquipmentProfile.homeGym.equipment,
        focus: const {Muscle.glute},
        excluded: const {'ex_b'},
        easyArea: EasyArea.knees,
        split: TrainingSplit.upperLower,
      ),
    );
  });

  test('has no answers while one is missing', () {
    expect(GeneratorQuestionsCubit(none).state.answers, isNull);
  });

  test('takes up to three focus muscles and toggles them off', () {
    final cubit = GeneratorQuestionsCubit(none)
      ..toggleFocus(Muscle.pec)
      ..toggleFocus(Muscle.lat)
      ..toggleFocus(Muscle.calf)
      ..toggleFocus(Muscle.biceps);
    expect(cubit.state.focus, {Muscle.pec, Muscle.lat, Muscle.calf});
    cubit.toggleFocus(Muscle.lat);
    expect(cubit.state.focus, {Muscle.pec, Muscle.calf});
  });

  test('the area to go easy on wins over focus muscles', () {
    final cubit = GeneratorQuestionsCubit(none)
      ..toggleFocus(Muscle.midDelt)
      ..toggleFocus(Muscle.pec)
      ..setEasyArea(EasyArea.shoulders);
    expect(cubit.state.focus, {Muscle.pec});
    cubit.toggleFocus(Muscle.rearDelt);
    expect(cubit.state.focus, {Muscle.pec});
    cubit.setEasyArea(null);
    expect(cubit.state.easyArea, isNull);
    expect(cubit.state.focus, {Muscle.pec});
  });

  test('a preset replaces the equipment', () {
    final cubit = GeneratorQuestionsCubit(none)
      ..toggleEquipment(Equipment.sled)
      ..applyPreset(EquipmentProfile.dumbbells);
    expect(cubit.state.equipment, EquipmentProfile.dumbbells.equipment);
  });

  test('a split needing more days than chosen is no answer', () {
    final cubit = answeredUpTo(GeneratorStep.split);
    expect(cubit.state.answered, isTrue);
    cubit
      ..back()
      ..back()
      ..back()
      ..back()
      ..back()
      ..back();
    expect(cubit.state.step, GeneratorStep.days);
    cubit
      ..setDays(2)
      ..setSplit(TrainingSplit.pushPullLegs);
    expect(cubit.state.splitFits(TrainingSplit.pushPullLegs), isFalse);
    expect(cubit.state.splitFits(TrainingSplit.fullBody), isTrue);
    while (!cubit.state.isLast) {
      cubit.next();
    }
    expect(cubit.state.answered, isFalse);
    cubit.setSplit(null);
    expect(cubit.state.answered, isTrue);
  });

  test('a later prefill fills only what is still unanswered', () {
    final cubit = GeneratorQuestionsCubit(none)..setGoal(Goal.loseFat);
    cubit.prefill((
      goal: Goal.buildMuscle,
      level: Level.beginner,
      daysPerWeek: 9,
      equipment: {Equipment.bodyweight, Equipment.rings},
    ));
    expect(cubit.state.goal, Goal.loseFat);
    expect(cubit.state.level, Level.beginner);
    expect(cubit.state.daysPerWeek, isNull);
    expect(cubit.state.equipment, {Equipment.rings});
    cubit
      ..toggleEquipment(Equipment.rings)
      ..prefill((
        goal: null,
        level: null,
        daysPerWeek: 4,
        equipment: {Equipment.sled},
      ));
    // Bodyweight only was the user's answer.
    expect(cubit.state.equipment, isEmpty);
    expect(cubit.state.daysPerWeek, 4);
  });
}
