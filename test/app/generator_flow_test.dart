import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/generator/domain/generator_repository.dart';
import 'package:get_workout/features/generator/presentation/generator_page.dart';
import 'package:get_workout/features/generator/presentation/generator_preview_cubit.dart';
import 'package:get_workout/features/generator/presentation/generator_preview_page.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/presentation/program_detail_page.dart';
import 'package:get_workout/features/subscription/presentation/paywall_page.dart';

import '../features/generator/fixtures.dart';
import 'training_world.dart';

void main() {
  final library = contentLibrary();

  TrainingWorld world({bool premium = true}) => TrainingWorld(
    exercises: library,
    premium: premium,
    profile: UserProfile(
      goal: Goal.buildMuscle,
      level: Level.intermediate,
      daysPerWeek: 4,
      equipment: EquipmentProfile.homeGym.equipment,
      onboardingCompletedAt: DateTime(2026),
    ),
  );

  GeneratorPreviewCubit preview(WidgetTester tester) =>
      BlocProvider.of<GeneratorPreviewCubit>(
        tester.element(find.byType(ListRow).first),
      );

  Future<void> openGenerator(WidgetTester tester, TrainingWorld app) async {
    await app.start(tester);
    await openTab(tester, 'Programs');
    await tapText(tester, 'Generate a program');
  }

  testWidgets('a premium user changes the days for this program, picks a '
      'focus area, keeps an exercise, regenerates and saves', (tester) async {
    final app = world();
    await openGenerator(tester, app);
    expect(find.byType(GeneratorPage), findsOneWidget);
    expect(find.text("We'll build it from your profile"), findsOneWidget);
    // Full gym: the equipment style question shows.
    expect(find.text('1 / 6'), findsOneWidget);

    // Three days fit two splits, so the split question joins.
    await tapText(tester, 'Days per week');
    await tapText(tester, '3 days');
    await tapText(tester, 'Continue');
    expect(find.text('1 / 7'), findsOneWidget);
    expect(app.profiles.profile.daysPerWeek, 4);

    await tapText(tester, 'Continue');
    expect(find.text('How long can a session be?'), findsOneWidget);
    await tapText(tester, '45 minutes');
    await tapText(tester, 'Continue');

    // The model cannot load in tests; the list picks the same.
    expect(find.text('Any areas to focus on?'), findsOneWidget);
    await tapText(tester, 'List');
    expect(
      find.text('They get more sets. Pick up to 2, or none.'),
      findsOneWidget,
    );
    await tapText(tester, 'Legs');
    await tapText(tester, 'Continue');

    expect(find.text("Any areas you'd rather not train?"), findsOneWidget);
    await tapText(tester, 'Continue');
    expect(find.text('Any sensitive areas?'), findsOneWidget);
    await tapText(tester, 'Knees');
    await tapText(tester, 'Continue');
    expect(find.text('What do you prefer to train with?'), findsOneWidget);
    await tapText(tester, 'Free weights');
    await tapText(tester, 'Continue');
    expect(find.text('How should the week be split?'), findsOneWidget);
    await tapText(tester, 'Create my program');

    expect(find.byType(GeneratorPreviewPage), findsOneWidget);
    final request = app.generator.requests.single;
    expect(request.answers.daysPerWeek, 3);
    expect(request.answers.sessionMinutes, 45);
    expect(request.answers.focus, {FocusArea.legs});
    expect(request.answers.sensitive, {SensitiveArea.knees});
    expect(request.answers.equipmentStyle, EquipmentStyle.freeWeights);
    expect(request.answers.splitId, isNull);
    expect(find.text('Full body · 3 days'), findsOneWidget);
    expect(preview(tester).state.program!.days, hasLength(3));

    // The row merges its button's label into its own.
    await tapOn(
      tester,
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Exercise options',
          )
          .first,
    );
    await tapText(tester, 'Keep when regenerating');
    expect(find.textContaining(' · Kept', findRichText: true), findsOneWidget);
    final (keptDay, keptId) = preview(tester).state.kept.single;

    await tapText(tester, 'Regenerate');
    expect(app.generator.requests.last.seed, 1);
    expect(
      app.generator.requests.last.kept[keptDay].map((item) => item.exerciseId),
      [keptId],
    );
    expect(find.textContaining(' · Kept', findRichText: true), findsOneWidget);

    await tapText(tester, 'Save program');

    final saved = app.programs.programs.values.single;
    expect(saved.name, 'Full body, 3 days');
    expect(saved.origin, ProgramOrigin.generated);
    expect(saved.days.map((day) => day.name), ['Day A', 'Day B', 'Day C']);
    expect(
      saved.days[keptDay].items.map((item) => item.exerciseId),
      contains(keptId),
    );
    expect(find.byType(ProgramDetailPage), findsOneWidget);

    await app.stop(tester);
  });

  testWidgets('offline, the questions and the preview say so and retry', (
    tester,
  ) async {
    final app = world();
    app.generator.watch = () => Stream.error(const NetworkFailure());
    await openGenerator(tester, app);
    expect(find.text("You're offline"), findsOneWidget);

    app.generator.watch = () => Stream.value(options);
    await tapText(tester, 'Retry');
    expect(find.text("We'll build it from your profile"), findsOneWidget);

    app.generator.answer = (_) => const Err(NetworkFailure());
    for (var i = 0; i < 5; i++) {
      await tapText(tester, 'Continue');
    }
    await tapText(tester, 'Create my program');
    expect(find.text("You're offline"), findsOneWidget);

    app.generator.answer = null;
    await tapText(tester, 'Retry');
    expect(find.text('Full body · 4 days'), findsOneWidget);

    await app.stop(tester);
  });

  testWidgets('answers no program fits go back to the questions', (
    tester,
  ) async {
    final app = world();
    await openGenerator(tester, app);
    app.generator.answer = (_) =>
        const Err(GenerationRefused(GenerationRefusal.noExercises, ''));
    for (var i = 0; i < 5; i++) {
      await tapText(tester, 'Continue');
    }
    await tapText(tester, 'Create my program');
    expect(find.text('No program fits these answers'), findsOneWidget);

    await tapText(tester, 'Change answers');
    expect(find.text('What do you prefer to train with?'), findsOneWidget);

    await app.stop(tester);
  });

  testWidgets('a free user gets the paywall instead', (tester) async {
    final app = world(premium: false);
    await openGenerator(tester, app);

    expect(find.byType(PaywallPage), findsOneWidget);
    expect(find.byType(GeneratorPage), findsNothing);

    await app.stop(tester);
  });
}
