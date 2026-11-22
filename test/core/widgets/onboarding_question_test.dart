import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/widgets/onboarding_question.dart';
import 'package:get_workout/l10n/app_localizations.dart';

import '../../component_harness.dart';

void main() {
  Future<void> pumpPage(WidgetTester tester, Widget page) => tester.pumpWidget(
    MaterialApp(
      theme: AppPreset.slate.lightTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: page,
    ),
  );

  testWidgets('progress up to the question, Back and Continue', (tester) async {
    var back = 0;
    var next = 0;
    await pumpPage(
      tester,
      OnboardingQuestion(
        step: 0,
        count: 9,
        onBack: () => back++,
        body: const OnboardingQuestionBody(
          title: "What's your main goal?",
          info: 'We use it to suggest your first program.',
          answer: SizedBox(height: 100),
        ),
        actionLabel: 'Continue',
        onAction: () => next++,
      ),
    );

    final progress = tester.widget<StepProgress>(find.byType(StepProgress));
    expect((progress.count, progress.current), (9, 1));
    expect(
      find.text('We use it to suggest your first program.'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.tap(find.text('Continue'));
    expect((back, next), (1, 1));
  });

  testWidgets('Continue waits for an answer', (tester) async {
    await pumpPage(
      tester,
      const OnboardingQuestion(
        step: 2,
        count: 9,
        onBack: null,
        body: OnboardingQuestionBody(title: 'Q', answer: SizedBox()),
        actionLabel: 'Continue',
        onAction: null,
      ),
    );

    final button = tester.widget<ForgeButton>(find.byType(ForgeButton));
    expect(button.onPressed, isNull);
    expect(button.size, ForgeButtonSize.large);
  });

  testWidgets('a choice answers with its value; one not enabled takes no tap', (
    tester,
  ) async {
    final picked = <String>[];
    await pumpComponent(
      tester,
      OnboardingChoices<String>(
        values: const ['muscle', 'strength', 'locked'],
        selected: 'muscle',
        title: (value) => value.toUpperCase(),
        subtitle: (value) =>
            value == 'muscle' ? 'Bigger, fuller muscles' : null,
        enabled: (value) => value != 'locked',
        onChanged: picked.add,
      ),
    );

    expect(find.text('Bigger, fuller muscles'), findsOneWidget);
    final grid = tester.widget<ChoiceGrid>(find.byType(ChoiceGrid));
    expect(grid.form, ChoiceListForm.stacked);
    expect(grid.selected, 0);
    expect(grid.options.map((option) => option.enabled), [true, true, false]);
    await tester.tap(find.text('STRENGTH'));
    await tester.tap(find.text('LOCKED'));
    expect(picked, ['strength']);
  });
  testWidgets('null can be an answer; no answer selects no row', (
    tester,
  ) async {
    Widget choices(String? selected) => OnboardingChoices<String?>(
      values: const [null, 'push'],
      selected: selected,
      title: (value) => value ?? 'none',
      onChanged: (_) {},
    );

    await pumpComponent(tester, choices(null));
    expect(tester.widget<ChoiceGrid>(find.byType(ChoiceGrid)).selected, 0);

    await pumpComponent(
      tester,
      OnboardingChoices<String>(
        values: const ['push'],
        selected: null,
        title: (value) => value,
        onChanged: (_) {},
      ),
    );
    expect(tester.widget<ChoiceGrid>(find.byType(ChoiceGrid)).selected, isNull);
  });
}
