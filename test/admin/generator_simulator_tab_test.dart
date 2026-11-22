import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/admin/exercises/domain/admin_exercise_repository.dart';
import 'package:get_workout/admin/exercises/domain/exercise_admin_usecases.dart';
import 'package:get_workout/admin/generator/domain/generator_rules.dart';
import 'package:get_workout/admin/generator/domain/generator_rules_usecases.dart';
import 'package:get_workout/admin/generator/domain/simulation.dart';
import 'package:get_workout/admin/generator/presentation/dosing_tab.dart';
import 'package:get_workout/admin/generator/presentation/generator_page.dart';
import 'package:get_workout/admin/generator/presentation/generator_rules_cubit.dart';
import 'package:get_workout/admin/generator/presentation/generator_simulator_cubit.dart';
import 'package:get_workout/admin/shell/unload_guard.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/generator/domain/generator_answers.dart';
import 'package:get_workout/features/generator/domain/generator_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';
import 'generator_fixtures.dart';

class MockExerciseRepository extends Mock implements AdminExerciseRepository {}

class _NoUnloadGuard implements UnloadGuard {
  @override
  set active(bool value) {}
}

void main() {
  final seed = seedRules();
  late MockRepository repository;

  setUpAll(() {
    registerFallbackValue(seed);
    registerFallbackValue(
      const SimulationRequest(
        answers: GeneratorAnswers(
          goal: Goal.buildMuscle,
          level: Level.beginner,
          daysPerWeek: 2,
          sessionMinutes: 60,
          equipment: {},
        ),
        seed: 0,
      ),
    );
  });

  setUp(() {
    repository = MockRepository();
    final exercises = MockExerciseRepository();
    when(() => repository.load())
        .thenAnswer((_) async => Ok(storedRules(rules: seed)));
    when(() => repository.check(any()))
        .thenAnswer((_) async => const Ok(RulesCheck()));
    when(() => repository.simulate(any()))
        .thenAnswer((_) async => Ok(simulation()));
    when(() => exercises.watchAll()).thenAnswer(
      (_) => Stream.value([
        record(validJson(id: 'bench_press', name: 'Bench Press')),
      ]),
    );
    sl
      ..registerFactory<GeneratorRulesCubit>(() => makeCubit(repository))
      ..registerFactory(
        () => GeneratorSimulatorCubit(
          simulateGenerator: SimulateGenerator(repository),
          watchExerciseRecords: WatchExerciseRecords(exercises),
        ),
      )
      ..registerSingleton<UnloadGuard>(_NoUnloadGuard());
  });

  tearDown(sl.reset);

  Future<void> openSimulator(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: ForgeTheme.light(), home: const GeneratorPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Simulator'));
    await tester.pumpAndSettle();
  }

  SimulationRequest sent() =>
      verify(() => repository.simulate(captureAny())).captured.last
          as SimulationRequest;

  testWidgets('shows the answers, runs them and explains the program', (
    tester,
  ) async {
    await openSimulator(tester);
    expect(find.text('Published v3'), findsOneWidget);
    expect(find.text('My changes'), findsNothing);
    for (final text in [
      'Build muscle',
      'Intermediate',
      '60 min',
      'Full gym',
      'No preference',
      'Let the rules choose',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.textContaining('press Generate'), findsOneWidget);

    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Chest'));
    await tester.pumpAndSettle();
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.text('Chest'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pumpAndSettle();
    final request = sent();
    expect(request.answers.focus, {FocusArea.chest});
    expect(request.rules, isNull);

    expect(find.text('Upper / Lower'), findsOneWidget);
    expect(
      find.text('template upper_lower_4 · 10 weeks · uncovered: abdominal'),
      findsOneWidget,
    );
    expect(find.widgetWithText(Tab, 'Upper A · 15 min'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Lower A · 8 min'), findsOneWidget);
    for (final text in [
      'Bench Press',
      'Primary · 1',
      '4 × 6–10',
      '150 s',
      '61.4',
      'plank',
      'Core · 2 · key',
      '3 × 30 s',
      '—',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(
      find.text(
        'Weekly sets: pec 4 / 16 · abdominal 1.5 / 6 · quads 3 / 12 · '
        'triceps 2',
      ),
      findsOneWidget,
    );

    const why =
        'tier 30 · equipment 12 · popularity 18.5 · variety 0.9 — next: '
        'dumbbell_press 44.1 · machine_press 39.8';
    expect(find.text(why), findsNothing);
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(find.text(why), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Lower A · 8 min'));
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsNothing);
    expect(find.text('Secondary · 1 · extra'), findsOneWidget);
    expect(find.text('15.0'), findsOneWidget);
    await tester.tap(find.text('leg_press'));
    await tester.pumpAndSettle();
    expect(find.text('tier 20 · above level -5'), findsOneWidget);
  });

  testWidgets('the answers and the result outlast switching tabs', (
    tester,
  ) async {
    await openSimulator(tester);
    await tester.tap(find.text('Sensitive'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Knees'));
    await tester.pumpAndSettle();
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, 'Dosing'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Simulator'));
    await tester.pumpAndSettle();
    expect(find.text('Knees'), findsOneWidget);
    expect(find.text('Upper / Lower'), findsOneWidget);
  });

  testWidgets('My changes runs the checked draft', (tester) async {
    await openSimulator(tester);
    await tester.tap(find.widgetWithText(Tab, 'Dosing'));
    await tester.pumpAndSettle();
    // An edit, checked a second later without problems.
    final cubit =
        tester.element(find.byType(DosingTab)).read<GeneratorRulesCubit>()
          ..setValue(['dosing', 'build_muscle', 'primary', 'restS'], 165);
    await tester.pump(GeneratorRulesCubit.checkDelay);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Simulator'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pumpAndSettle();
    expect(sent().rules, cubit.state.draft);
  });

  testWidgets('a refusal says so in words and keeps the answers', (
    tester,
  ) async {
    when(() => repository.simulate(any())).thenAnswer(
      (_) async => const Err(
        GenerationRefused(GenerationRefusal.noExercises, 'no exercises'),
      ),
    );
    await openSimulator(tester);
    await tester.tap(find.text('Level'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pumpAndSettle();
    expect(
      find.text('No program: these answers leave a day without an exercise.'),
      findsOneWidget,
    );
    expect(find.text('Advanced'), findsOneWidget);
  });
}
