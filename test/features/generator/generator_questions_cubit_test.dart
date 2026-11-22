import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/generator/domain/generator_options.dart';
import 'package:get_workout/features/generator/domain/generator_usecases.dart';
import 'package:get_workout/features/generator/presentation/generator_questions_cubit.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';

import 'fixtures.dart';

void main() {
  late FakeGeneratorRepository repository;

  setUp(() => repository = FakeGeneratorRepository());

  /// The questions over [repository]'s options, once they arrived.
  Future<GeneratorQuestionsCubit> build({
    Goal? goal = Goal.buildMuscle,
    Level? level = Level.intermediate,
    int? days = 4,
    Set<Equipment>? equipment,
  }) async {
    final cubit = GeneratorQuestionsCubit((
      goal: goal,
      level: level,
      daysPerWeek: days,
      equipment: equipment ?? EquipmentProfile.homeGym.equipment,
    ), watchOptions: WatchGeneratorOptions(repository));
    addTearDown(cubit.close);
    await pumpEventQueue();
    return cubit;
  }

  Future<GeneratorQuestionsCubit> at(
    GeneratorStep step, {
    int days = 4,
    Set<Equipment>? equipment,
  }) async {
    final cubit = await build(days: days, equipment: equipment);
    while (cubit.state.step != step) {
      cubit.next();
    }
    return cubit;
  }

  group('the options', () {
    test('load before the questions, the session at 60 minutes', () async {
      repository.watch = pending;
      final waiting = GeneratorQuestionsCubit((
        goal: null,
        level: null,
        daysPerWeek: null,
        equipment: null,
      ), watchOptions: WatchGeneratorOptions(repository));
      addTearDown(waiting.close);
      expect(waiting.state.status, OptionsStatus.loading);
      expect(waiting.state.answers, isNull);

      repository.watch = () => Stream.value(options);
      final cubit = await build();
      expect(cubit.state.status, OptionsStatus.ready);
      expect(cubit.state.options, options);
      expect(cubit.state.sessionMinutes, 60);
    });

    for (final (failure, status) in [
      (const NetworkFailure(), OptionsStatus.offline),
      (const NotFoundFailure(), OptionsStatus.unavailable),
      (const UnknownFailure(), OptionsStatus.failure),
    ]) {
      test('that fail show ${status.name}, and Retry reads again', () async {
        repository.watch = () => Stream.error(failure);
        final cubit = await build();
        expect(cubit.state.status, status);

        repository.watch = () => Stream.value(options);
        cubit.retry();
        await pumpEventQueue();
        expect(cubit.state.status, OptionsStatus.ready);
      });
    }

    test('once loaded stay through a later failure', () async {
      final options$ = StreamController<GeneratorOptions>();
      repository.watch = () => options$.stream;
      final cubit = await build();
      options$
        ..add(options)
        ..addError(const NetworkFailure());
      await pumpEventQueue();
      expect(cubit.state.status, OptionsStatus.ready);
      await options$.close();
    });

    test('that change keep the answers they still offer', () async {
      final options$ = StreamController<GeneratorOptions>();
      repository.watch = () => options$.stream;
      final cubit = await build(days: 3);
      options$.add(options);
      await pumpEventQueue();
      cubit
        ..setSessionMinutes(90)
        ..toggleFocus(FocusArea.legs)
        ..toggleFocus(FocusArea.arms);

      options$.add(
        GeneratorOptions(
          splits: options.splits,
          sessionMinutes: const [30, 45],
          maxFocusAreas: 1,
          maxSkipAreas: 3,
        ),
      );
      await pumpEventQueue();
      expect(cubit.state.sessionMinutes, 45);
      expect(cubit.state.focus, hasLength(1));
      await options$.close();
    });
  });

  group('the profile page', () {
    test('is prefilled; bodyweight is not equipment', () async {
      final cubit = await build(
        goal: Goal.loseFat,
        level: Level.beginner,
        days: 3,
        equipment: {Equipment.bodyweight, Equipment.dumbbell},
      );
      expect(cubit.state.goal, Goal.loseFat);
      expect(cubit.state.level, Level.beginner);
      expect(cubit.state.daysPerWeek, 3);
      expect(cubit.state.equipment, {Equipment.dumbbell});
    });

    test('leaves days out of range unanswered and waits for them', () async {
      final cubit = await build(days: 7);
      expect(cubit.state.daysPerWeek, isNull);
      expect(cubit.state.answered, false);
      cubit.next();
      expect(cubit.state.step, GeneratorStep.profile);

      cubit.prefill((
        goal: Goal.getStronger,
        level: null,
        daysPerWeek: 5,
        equipment: null,
      ));
      // Only what was missing is filled.
      expect(cubit.state.goal, Goal.buildMuscle);
      expect(cubit.state.daysPerWeek, 5);
      cubit.next();
      expect(cubit.state.step, GeneratorStep.session);
    });

    test('changes an answer for this program', () async {
      final cubit = await build();
      cubit.changeProfile(
        const UserProfile(
          goal: Goal.getStronger,
          level: Level.intermediate,
          daysPerWeek: 6,
          equipment: {Equipment.bodyweight, Equipment.barbell},
        ),
      );
      expect(cubit.state.goal, Goal.getStronger);
      expect(cubit.state.daysPerWeek, 6);
      expect(cubit.state.equipment, {Equipment.barbell});
      expect(cubit.state.answers!.daysPerWeek, 6);
    });
  });

  group('the pages', () {
    const always = [
      GeneratorStep.profile,
      GeneratorStep.session,
      GeneratorStep.focus,
      GeneratorStep.skip,
      GeneratorStep.sensitive,
    ];

    test('without style or split question are five', () async {
      // Home gym: free weights only; four days: upper/lower only.
      final cubit = await build();
      expect(cubit.state.steps, always);
    });

    test('ask the style when the equipment has both kinds', () async {
      final cubit = await build(equipment: EquipmentProfile.fullGym.equipment);
      expect(cubit.state.steps, [...always, GeneratorStep.style]);
    });

    test('ask the split when several fit', () async {
      final cubit = await build(days: 3);
      expect(cubit.state.steps, [...always, GeneratorStep.split]);
    });

    test('ask both when both apply', () async {
      final cubit = await build(
        days: 3,
        equipment: EquipmentProfile.fullGym.equipment,
      );
      expect(cubit.state.steps, [
        ...always,
        GeneratorStep.style,
        GeneratorStep.split,
      ]);
    });

    test('follow a profile change', () async {
      final cubit = await build();
      cubit.changeProfile(
        UserProfile(
          goal: Goal.buildMuscle,
          level: Level.intermediate,
          daysPerWeek: 3,
          equipment: EquipmentProfile.fullGym.equipment,
        ),
      );
      expect(cubit.state.steps, hasLength(7));
    });

    test('step back to the nearest page when the one on screen goes', () async {
      final options$ = StreamController<GeneratorOptions>();
      repository.watch = () => options$.stream;
      final cubit = await build(days: 3);
      options$.add(options);
      await pumpEventQueue();
      while (cubit.state.step != GeneratorStep.split) {
        cubit.next();
      }

      // Only full body fits three days now: no split question.
      options$.add(
        GeneratorOptions(
          splits: options.splits.where((s) => s.id != 'ppl').toList(),
          sessionMinutes: options.sessionMinutes,
          maxFocusAreas: 2,
          maxSkipAreas: 3,
        ),
      );
      await pumpEventQueue();
      expect(cubit.state.step, GeneratorStep.sensitive);
      expect(cubit.state.steps.indexOf(cubit.state.step), 4);
      expect(cubit.state.steps, hasLength(5));
      expect(cubit.state.isLast, true);
      cubit.next();
      expect(cubit.state.step, GeneratorStep.sensitive);
      expect(cubit.back(), true);
      expect(cubit.state.step, GeneratorStep.skip);
      cubit.next();
      expect(cubit.state.step, GeneratorStep.sensitive);
      await options$.close();
    });

    test('go forward and back, and end on the last one', () async {
      final cubit = await build(days: 3);
      expect(cubit.back(), false);
      for (final step in cubit.state.steps.skip(1)) {
        cubit.next();
        expect(cubit.state.step, step);
      }
      expect(cubit.state.isLast, true);
      cubit.next();
      expect(cubit.state.step, GeneratorStep.split);
      expect(cubit.back(), true);
      expect(cubit.state.step, GeneratorStep.sensitive);
    });
  });

  group('focus and areas to leave out', () {
    test('focus areas stop at the most allowed', () async {
      final cubit = await at(GeneratorStep.focus);
      cubit
        ..toggleFocus(FocusArea.chest)
        ..toggleFocus(FocusArea.back)
        ..toggleFocus(FocusArea.legs);
      expect(cubit.state.focus, {FocusArea.chest, FocusArea.back});
      cubit.toggleFocus(FocusArea.chest);
      expect(cubit.state.focus, {FocusArea.back});
    });

    test('a focus area cannot be left out', () async {
      final cubit = await at(GeneratorStep.skip);
      cubit
        ..toggleFocus(FocusArea.chest)
        ..toggleSkip(FocusArea.chest);
      expect(cubit.state.skip, isEmpty);
    });

    test('areas to leave out stop at the most allowed', () async {
      final cubit = await at(GeneratorStep.skip);
      for (final area in FocusArea.values) {
        cubit.toggleSkip(area);
      }
      expect(cubit.state.skip, {
        FocusArea.chest,
        FocusArea.back,
        FocusArea.shoulders,
      });
      cubit.toggleSkip(FocusArea.back);
      expect(cubit.state.skip, {FocusArea.chest, FocusArea.shoulders});
    });

    test('picking a left-out area as focus takes it out', () async {
      final cubit = await at(GeneratorStep.skip);
      cubit
        ..toggleSkip(FocusArea.legs)
        ..toggleSkip(FocusArea.arms)
        ..back()
        ..toggleFocus(FocusArea.legs);
      expect(cubit.state.focus, {FocusArea.legs});
      expect(cubit.state.skip, {FocusArea.arms});
    });
  });

  group('sensitive areas', () {
    test('start with none and take any number', () async {
      final cubit = await at(GeneratorStep.sensitive);
      expect(cubit.state.sensitive, isEmpty);
      cubit
        ..toggleSensitive(SensitiveArea.knees)
        ..toggleSensitive(SensitiveArea.hips)
        ..toggleSensitive(SensitiveArea.lowerBack);
      expect(cubit.state.sensitive, hasLength(3));
      cubit.toggleSensitive(SensitiveArea.hips);
      expect(cubit.state.sensitive, {
        SensitiveArea.knees,
        SensitiveArea.lowerBack,
      });
    });

    test('"No sensitive areas" clears them', () async {
      final cubit = await at(GeneratorStep.sensitive);
      cubit
        ..toggleSensitive(SensitiveArea.knees)
        ..clearSensitive();
      expect(cubit.state.sensitive, isEmpty);
    });
  });

  group('the answers', () {
    test('hold every page\'s answer', () async {
      final cubit = await build(
        days: 3,
        equipment: EquipmentProfile.fullGym.equipment,
      );
      cubit
        ..setSessionMinutes(45)
        ..toggleFocus(FocusArea.glutes)
        ..toggleSkip(FocusArea.arms)
        ..toggleSensitive(SensitiveArea.knees)
        ..setEquipmentStyle(EquipmentStyle.machines)
        ..setSplit('ppl');
      expect(
        cubit.state.answers,
        answers(
          days: 3,
          minutes: 45,
          focus: {FocusArea.glutes},
          skip: {FocusArea.arms},
          sensitive: {SensitiveArea.knees},
          style: EquipmentStyle.machines,
          split: 'ppl',
        ),
      );
    });

    test('drop a style or split whose question no longer shows', () async {
      final cubit = await build(
        days: 3,
        equipment: EquipmentProfile.fullGym.equipment,
      );
      cubit
        ..setEquipmentStyle(EquipmentStyle.freeWeights)
        ..setSplit('ppl')
        ..changeProfile(
          UserProfile(
            goal: Goal.buildMuscle,
            level: Level.intermediate,
            daysPerWeek: 4,
            equipment: EquipmentProfile.homeGym.equipment,
          ),
        );
      final given = cubit.state.answers!;
      expect(given.equipmentStyle, EquipmentStyle.any);
      expect(given.splitId, isNull);
    });

    test('let the app choose the split by default', () async {
      final cubit = await build(days: 3);
      expect(cubit.state.answers!.splitId, isNull);
      cubit
        ..setSplit('full_body')
        ..setSplit(null);
      expect(cubit.state.answers!.splitId, isNull);
    });
  });
}
