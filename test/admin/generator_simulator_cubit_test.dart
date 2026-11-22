import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/exercises/domain/admin_exercise_repository.dart';
import 'package:get_workout/admin/exercises/domain/exercise_admin_usecases.dart';
import 'package:get_workout/admin/generator/domain/generator_rules.dart';
import 'package:get_workout/admin/generator/domain/generator_rules_usecases.dart';
import 'package:get_workout/admin/generator/domain/simulation.dart';
import 'package:get_workout/admin/generator/presentation/generator_rules_cubit.dart';
import 'package:get_workout/admin/generator/presentation/generator_simulator_cubit.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/generator/domain/generator_answers.dart';
import 'package:get_workout/features/generator/domain/generator_repository.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';
import 'generator_fixtures.dart';

class MockExerciseRepository extends Mock implements AdminExerciseRepository {}

void main() {
  final seed = seedRules();
  final published = storedRules(rules: seed);
  // Unpublished rules with other session lengths, one split and focus max 1.
  final draft = seed
      .set(['time', 'sessionMinutes'], [30, 45])
      .set(['splits'], [seed.splits.first])
      .set(['focus', 'max'], 1);
  late MockRepository repository;
  late MockExerciseRepository exercises;

  setUpAll(() {
    registerFallbackValue(const SimulationRequest(answers: _answers, seed: 0));
  });

  setUp(() {
    repository = MockRepository();
    exercises = MockExerciseRepository();
    when(() => repository.simulate(any()))
        .thenAnswer((_) async => Ok(simulation()));
    when(() => exercises.watchAll()).thenAnswer(
      (_) => Stream.value([
        record(validJson(id: 'bench_press', name: 'Bench Press')),
      ]),
    );
  });

  GeneratorSimulatorCubit build() => GeneratorSimulatorCubit(
    simulateGenerator: SimulateGenerator(repository),
    watchExerciseRecords: WatchExerciseRecords(exercises),
  );

  GeneratorSimulatorCubit withRules({GeneratorRules? draft}) {
    final cubit = build()
      ..setRules(
        published: published,
        draft: draft,
        draftCheck: draft == null ? DraftCheck.unchanged : DraftCheck.ready,
      );
    addTearDown(cubit.close);
    return cubit;
  }

  test('starts from the defaults on the published rules', () {
    final state = withRules().state;
    expect(state.sources, [RulesSource.published]);
    expect(state.source, RulesSource.published);
    expect(state.rules, seed);
    expect(state.goal, Goal.buildMuscle);
    expect(state.level, Level.intermediate);
    expect(state.daysPerWeek, 4);
    expect(state.sessionMinutes, 60);
    expect(state.sessionOptions, [30, 45, 60, 75, 90]);
    expect(state.equipment, EquipmentProfile.fullGym);
    expect(state.equipmentStyle, EquipmentStyle.any);
    expect(state.focus, isEmpty);
    expect(state.skip, isEmpty);
    expect(state.sensitive, isEmpty);
    expect(state.split, isNull);
    expect(state.seed, 0);
    expect(state.status, SimulationStatus.idle);
    expect(state.canGenerate, isTrue);
  });

  group('focus and leave out', () {
    test('a focus area is never left out, and each keeps its maximum', () {
      final cubit = withRules()
        ..toggleSkip(FocusArea.chest)
        ..toggleFocus(FocusArea.chest);
      expect(cubit.state.focus, {FocusArea.chest});
      expect(cubit.state.skip, isEmpty);

      cubit.toggleSkip(FocusArea.chest);
      expect(cubit.state.skip, isEmpty, reason: 'chest is in focus');

      cubit
        ..toggleFocus(FocusArea.back)
        ..toggleFocus(FocusArea.arms);
      expect(cubit.state.focus, {FocusArea.chest, FocusArea.back});

      cubit
        ..toggleSkip(FocusArea.legs)
        ..toggleSkip(FocusArea.core)
        ..toggleSkip(FocusArea.glutes)
        ..toggleSkip(FocusArea.arms);
      expect(cubit.state.skip, {
        FocusArea.legs,
        FocusArea.core,
        FocusArea.glutes,
      });

      cubit.toggleFocus(FocusArea.back);
      expect(cubit.state.focus, {FocusArea.chest});
    });
  });

  group('rules', () {
    test(
      'My changes is offered only with a runnable draft and sends it',
      () async {
        final cubit = withRules(draft: draft);
        expect(cubit.state.sources, [RulesSource.published, RulesSource.draft]);
        expect(cubit.state.source, RulesSource.published);

        cubit.selectSource(RulesSource.draft);
        expect(cubit.state.rules, draft);
        await cubit.generate();
        final sent =
            verify(() => repository.simulate(captureAny())).captured.single
                as SimulationRequest;
        expect(sent.rules, draft);

        cubit.selectSource(RulesSource.published);
        await cubit.generate();
        final again =
            verify(() => repository.simulate(captureAny())).captured.single
                as SimulationRequest;
        expect(again.rules, isNull);
      },
    );

    test('My changes stays chosen while the draft is checked, and falls '
        'back only without changes or with problems', () async {
      final cubit = withRules(draft: draft)
        ..selectSource(RulesSource.draft)
        ..setRules(
          published: published,
          draft: draft,
          draftCheck: DraftCheck.checking,
        );
      expect(cubit.state.source, RulesSource.draft);
      expect(cubit.state.requested, RulesSource.draft);
      expect(cubit.state.canGenerate, isFalse);
      await cubit.generate();
      verifyNever(() => repository.simulate(any()));

      cubit.setRules(
        published: published,
        draft: draft,
        draftCheck: DraftCheck.unchecked,
      );
      expect(cubit.state.source, RulesSource.draft);
      expect(cubit.state.canGenerate, isFalse);

      cubit.setRules(
        published: published,
        draft: draft,
        draftCheck: DraftCheck.problems,
      );
      expect(cubit.state.sources, [RulesSource.published]);
      expect(cubit.state.source, RulesSource.published);
      expect(cubit.state.fallback, DraftCheck.problems);
      expect(cubit.state.canGenerate, isTrue);

      cubit.setRules(published: published);
      expect(cubit.state.source, RulesSource.published);
      expect(cubit.state.fallback, DraftCheck.unchanged);

      cubit.selectSource(RulesSource.published);
      expect(cubit.state.fallback, isNull);
    });

    test('with no rules published only My changes exists', () {
      final cubit = build()
        ..setRules(
          published: const StoredRules(version: 0),
          draft: draft,
          draftCheck: DraftCheck.ready,
        );
      addTearDown(cubit.close);
      expect(cubit.state.sources, [RulesSource.draft]);
      expect(cubit.state.source, RulesSource.draft);
      cubit.selectSource(RulesSource.published);
      expect(cubit.state.source, RulesSource.draft);
    });

    test('the session, split and focus follow the chosen rules', () {
      final cubit = withRules(draft: draft)
        ..setSplit('push_pull_legs')
        ..toggleFocus(FocusArea.chest)
        ..toggleFocus(FocusArea.back);
      expect(cubit.state.split, 'push_pull_legs');
      expect(cubit.state.splits.length, seed.splits.length);

      cubit.selectSource(RulesSource.draft);
      expect(cubit.state.sessionOptions, [30, 45]);
      // 60 is not offered: the middle one.
      expect(cubit.state.sessionMinutes, 45);
      expect(cubit.state.splits, [seed.splits.first]);
      expect(cubit.state.split, isNull);
      expect(cubit.state.focus, {FocusArea.chest});

      cubit
        ..setSessionMinutes(60)
        ..setSplit('push_pull_legs');
      expect(cubit.state.sessionMinutes, 45);
      expect(cubit.state.split, isNull);
    });
  });

  group('generate', () {
    test('runs the answers: running, then the result with its rules and '
        'the exercise names', () async {
      final cubit = withRules()
        ..setDays(3)
        ..setEquipment(EquipmentProfile.dumbbells)
        ..toggleSensitive(SensitiveArea.knees)
        ..setSeed(5);
      final statuses = <SimulationStatus>[];
      final listening = cubit.stream.listen((s) => statuses.add(s.status));
      addTearDown(listening.cancel);
      await cubit.generate();
      await pumpEventQueue();

      // The names may arrive while it runs.
      expect(statuses.first, SimulationStatus.running);
      expect(statuses.last, SimulationStatus.done);
      final state = cubit.state;
      expect(state.run?.simulation, simulation());
      expect(state.run?.rules, seed);
      expect(state.names, {'bench_press': 'Bench Press'});
      final sent =
          verify(() => repository.simulate(captureAny())).captured.single
              as SimulationRequest;
      expect(sent, state.run?.request);
      expect(sent.seed, 5);
      expect(sent.rules, isNull);
      expect(sent.answers.daysPerWeek, 3);
      expect(sent.answers.equipment, EquipmentProfile.dumbbells.equipment);
      expect(sent.answers.sensitive, {SensitiveArea.knees});
      expect(sent.answers.sessionMinutes, 60);
    });

    test('a failure keeps the answers and drops the last result', () async {
      final cubit = withRules()..setDays(5);
      await cubit.generate();
      expect(cubit.state.run, isNotNull);

      when(() => repository.simulate(any())).thenAnswer(
        (_) async => const Err(
          GenerationRefused(GenerationRefusal.noTemplate, 'no template'),
        ),
      );
      await cubit.generate();
      expect(cubit.state.status, SimulationStatus.failed);
      expect(cubit.state.failure, isA<GenerationRefused>());
      expect(cubit.state.run, isNull);
      expect(cubit.state.daysPerWeek, 5);
    });

    test('a day and a row open; a new run opens the first day', () async {
      final cubit = withRules();
      await cubit.generate();
      cubit
        ..selectDay(1)
        ..toggleRow(0);
      expect((cubit.state.day, cubit.state.openRow), (1, 0));
      cubit.toggleRow(0);
      expect(cubit.state.openRow, isNull);
      cubit.toggleRow(0);
      await cubit.generate();
      expect((cubit.state.day, cubit.state.openRow), (0, null));
    });

    test('without rules nothing runs', () async {
      final cubit = build();
      addTearDown(cubit.close);
      expect(cubit.state.canGenerate, isFalse);
      await cubit.generate();
      verifyNever(() => repository.simulate(any()));
    });
  });

  test('closing during a run emits nothing more', () async {
    final answer = Completer<Result<Simulation>>();
    when(() => repository.simulate(any())).thenAnswer((_) => answer.future);
    final cubit = build()..setRules(published: published);
    final statuses = <SimulationStatus>[];
    final listening = cubit.stream.listen((s) => statuses.add(s.status));
    addTearDown(listening.cancel);
    final run = cubit.generate();
    await pumpEventQueue();
    expect(statuses.last, SimulationStatus.running);
    final before = statuses.length;
    await cubit.close();
    answer.complete(Ok(simulation()));
    await run;
    expect(statuses, hasLength(before));
  });

  test('a published run of another version than the loaded one says so', () {
    final cubit = withRules();
    expect(cubit.state.runVersionDiffers, isFalse);
    when(() => repository.simulate(any()))
        .thenAnswer((_) async => Ok(simulation(rulesVersion: 2)));
    return cubit.generate().then((_) {
      expect(cubit.state.runVersionDiffers, isTrue);
    });
  });

  test('a day lasts the app estimate plus the setup time per exercise', () {
    const day = ProgramDay(
      items: [
        ProgramItem(
          exerciseId: 'a',
          sets: 4,
          repMin: 6,
          repMax: 10,
          restS: 150,
        ),
        ProgramItem(exerciseId: 'b', sets: 3, durationS: 30, restS: 45),
      ],
    );
    // 696 s + 225 s, plus 45 s setup for each of two: 1011 s.
    expect(dayMinutes(day, seed), 17);
    expect(dayMinutes(day, seed.set(['time', 'setupS'], 0)), 15);
  });

  test('weekly targets add the focus extra sets for focus muscles', () {
    final targets = weeklyTargets(seed, _answers, const [
      Muscle.pec,
      Muscle.lat,
      Muscle.calf,
    ]);
    // Intermediate: pec 12 + 4 for chest in focus, lat 12, calf 6.
    expect(targets, {Muscle.pec: 16.0, Muscle.lat: 12.0, Muscle.calf: 6.0});
  });
}

const _answers = GeneratorAnswers(
  goal: Goal.buildMuscle,
  level: Level.intermediate,
  daysPerWeek: 4,
  sessionMinutes: 60,
  equipment: {},
  focus: {FocusArea.chest},
);
