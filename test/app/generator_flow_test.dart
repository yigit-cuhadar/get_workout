import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/generator/presentation/generator_page.dart';
import 'package:get_workout/features/generator/presentation/generator_preview_cubit.dart';
import 'package:get_workout/features/generator/presentation/generator_preview_page.dart';
import 'package:get_workout/features/programs/presentation/program_detail_page.dart';
import 'package:get_workout/features/subscription/presentation/paywall_page.dart';

import '../features/generator/fixtures.dart';
import 'training_world.dart';

void main() {
  // The library the app ships with, so the generator has what it needs.
  final library = contentLibrary();

  GeneratorPreviewCubit preview(WidgetTester tester) =>
      BlocProvider.of<GeneratorPreviewCubit>(
        tester.element(find.byType(ListRow).first),
      );

  testWidgets('a premium user answers, keeps an exercise, regenerates and '
      'saves', (tester) async {
    final app = TrainingWorld(exercises: library, premium: true);
    await app.start(tester);
    await openTab(tester, 'Programs');

    await tapText(tester, 'Generate a program');
    expect(find.byType(GeneratorPage), findsOneWidget);
    for (final answer in ['Build muscle', 'Beginner', '3 days', '45 minutes']) {
      await tapText(tester, answer);
      await tapText(tester, 'Continue');
    }
    // The rest keep what the equipment owned and the defaults say.
    for (var i = 0; i < 8 && find.text('Continue').evaluate().isNotEmpty; i++) {
      await tapText(tester, 'Continue');
    }
    await tapText(tester, 'Create my program');

    expect(find.byType(GeneratorPreviewPage), findsOneWidget);
    expect(find.text('Your program'), findsOneWidget);
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
    final seed = preview(tester).state.seed;

    await tapText(tester, 'Regenerate');
    expect(preview(tester).state.seed, isNot(seed));
    expect(find.textContaining(' · Kept', findRichText: true), findsOneWidget);
    expect(
      preview(tester).state.program!.days[keptDay].items
          .map((item) => item.exerciseId),
      contains(keptId),
    );

    await tapText(tester, 'Save program');

    final saved = app.programs.programs.values.single;
    expect(saved.days, hasLength(3));
    expect(
      saved.days[keptDay].items.map((item) => item.exerciseId),
      contains(keptId),
    );
    expect(find.byType(ProgramDetailPage), findsOneWidget);
    expect(find.text(saved.name), findsWidgets);

    await app.stop(tester);
  });

  testWidgets('a free user gets the paywall instead', (tester) async {
    final app = TrainingWorld(exercises: library);
    await app.start(tester);
    await openTab(tester, 'Programs');

    await tapText(tester, 'Generate a program');

    expect(find.byType(PaywallPage), findsOneWidget);
    expect(find.byType(GeneratorPage), findsNothing);

    await app.stop(tester);
  });
}
