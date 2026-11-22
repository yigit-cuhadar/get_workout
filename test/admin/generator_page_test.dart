import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/admin/generator/domain/generator_rules.dart';
import 'package:get_workout/admin/generator/presentation/generator_page.dart';
import 'package:get_workout/admin/generator/presentation/generator_rules_cubit.dart';
import 'package:mocktail/mocktail.dart';

import 'generator_fixtures.dart';

const _rest = ['dosing', 'build_muscle', 'primary', 'restS'];

Finding _finding(FindingKind kind, {int days = 2, String detail = ''}) =>
    Finding(
      goal: 'lose_fat',
      level: 'beginner',
      daysPerWeek: days,
      equipment: 'bands',
      kind: kind,
      detail: detail,
    );

void main() {
  final seed = seedRules();
  late MockRepository repository;
  late GeneratorRulesCubit cubit;

  setUpAll(() {
    registerFallbackValue(seed);
    registerFallbackValue(RulesPublish(base: 0, rules: seed));
  });

  setUp(() {
    repository = MockRepository();
    when(() => repository.load())
        .thenAnswer((_) async => Ok(storedRules(rules: seed)));
    when(() => repository.check(any()))
        .thenAnswer((_) async => const Ok(RulesCheck()));
    cubit = makeCubit(repository);
    sl.registerFactory<GeneratorRulesCubit>(() => cubit);
  });

  tearDown(sl.reset);

  Future<void> pumpPage(WidgetTester tester, {Key? key}) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ForgeTheme.light(),
        home: GeneratorPage(key: key),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lets the debounced check run.
  Future<void> settleCheck(WidgetTester tester) async {
    await tester.pump(GeneratorRulesCubit.checkDelay);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the version, the tabs and, once edited, the bar', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('Generator'), findsOneWidget);
    expect(
      find.text('Version 3 · published 22 Nov 2026 by admin@example.com'),
      findsOneWidget,
    );
    for (final tab in ['Templates', 'Dosing', 'Volume', 'Selection', 'Areas']) {
      expect(find.widgetWithText(Tab, tab), findsOneWidget);
    }
    expect(find.text('Review and publish'), findsNothing);
    expect(find.text('History'), findsOneWidget);

    cubit
      ..setValue(_rest, 165)
      ..setValue(['volume', 'cap', 'beginner'], 16);
    await settleCheck(tester);
    expect(find.text('2 unpublished changes · Dosing, Volume'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review and publish'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard'), findsNothing);
  });

  testWidgets('version 0 says the import seeds the rules', (tester) async {
    when(() => repository.load())
        .thenAnswer((_) async => const Ok(StoredRules(version: 0)));
    await pumpPage(tester);
    expect(find.text('No rules published yet'), findsOneWidget);
    expect(find.textContaining('The content import seeds'), findsOneWidget);
  });

  testWidgets('problems sit in a card, on their tab and under the field', (
    tester,
  ) async {
    when(() => repository.check(any())).thenAnswer(
      (_) async => const Ok(
        RulesCheck(
          problems: [
            'dosing.build_muscle.primary.restS: must be a whole number from '
                '0 to 600',
          ],
        ),
      ),
    );
    final semantics = tester.ensureSemantics();
    await pumpPage(tester);
    cubit.setValue(_rest, 900);
    await settleCheck(tester);
    expect(find.text('1 problem blocks saving'), findsOneWidget);
    expect(find.text('Dosing · Build muscle · Primary · rest'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Dosing, has problems')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review and publish'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Dosing · Build muscle · Primary · rest'));
    await tester.pumpAndSettle();
    expect(cubit.state.tab.label, 'Dosing');
    // On the card and under the field.
    expect(find.text('must be a whole number from 0 to 600'), findsNWidgets(2));
    semantics.dispose();
  });

  testWidgets('the Dosing table edits a number and shows what it was', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.widgetWithText(Tab, 'Dosing'));
    await tester.pumpAndSettle();
    expect(find.text('Sets, beginner'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '150'), '165');
    await settleCheck(tester);
    expect(cubit.state.valueAt(_rest), 165);
    expect(find.text('was 150'), findsOneWidget);
    expect(find.text('1 unpublished change · Dosing'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Lose fat'));
    await tester.pumpAndSettle();
    expect(find.text('was 150'), findsNothing);
  });

  testWidgets('the Templates tab adds, moves and removes slots, and picks', (
    tester,
  ) async {
    final t = seedTemplate('upper_lower_4');
    final slots = ['templates', t, 'dayList', 0, 'slots'];
    final before = seed.at(slots)! as List;
    await pumpPage(tester);
    await tester.tap(find.text('upper_lower_4 · 4 days'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Upper A'), findsOneWidget);
    expect(find.text('Picks an exercise with'), findsOneWidget);

    await tester.ensureVisible(find.text('Add slot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add slot'));
    await tester.pumpAndSettle();
    expect(cubit.state.valueAt(slots), hasLength(before.length + 1));
    expect(
      cubit.state.changes.single.where,
      'Template upper_lower_4 · Upper A · slot ${before.length + 1} added',
    );

    await tester.tap(find.byTooltip('Remove slot').last);
    await tester.pumpAndSettle();
    expect(cubit.state.hasChanges, isFalse);

    await tester.tap(find.byTooltip('Move down').first);
    await tester.pumpAndSettle();
    expect((cubit.state.valueAt(slots)! as List)[1], before[0]);

    await tester.tap(find.byTooltip('Move up').at(1));
    await tester.pumpAndSettle();
    expect(cubit.state.hasChanges, isFalse);

    await tester.tap(find.byTooltip('Edit picks').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Isolation'));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await settleCheck(tester);
    expect(cubit.state.valueAt([...slots, 0, 'pick']), {
      ...(before[0] as Map)['pick'] as Map,
      'mechanic': 'isolation',
    });
    expect(find.text('was Horizontal push, Pec'), findsOneWidget);
  });

  testWidgets('the review lists the changes and the warning counts', (
    tester,
  ) async {
    final draft = seed.set(_rest, 165);
    when(() => repository.check(draft)).thenAnswer(
      (_) async => Ok(
        RulesCheck(
          findings: [
            _finding(FindingKind.short, detail: 'Full Body A: 24 min'),
            _finding(FindingKind.short, detail: 'Full Body B: 26 min'),
            _finding(FindingKind.short, days: 3),
            _finding(FindingKind.uncovered, detail: 'calf'),
          ],
        ),
      ),
    );
    when(() => repository.check(seed)).thenAnswer(
      (_) async => Ok(RulesCheck(findings: [_finding(FindingKind.short)])),
    );
    when(() => repository.publish(any())).thenAnswer((_) async {
      when(() => repository.load())
          .thenAnswer((_) async => Ok(storedRules(version: 4, rules: draft)));
      return const Ok(4);
    });
    await pumpPage(tester);
    cubit.setValue(_rest, 165);
    await settleCheck(tester);

    await tester.tap(find.text('Review and publish'));
    await tester.pumpAndSettle();
    expect(
      find.text('Publish version 4 of the generator rules'),
      findsOneWidget,
    );
    expect(find.text('Dosing · Build muscle · Primary · rest'), findsOneWidget);
    expect(find.text('150 s'), findsOneWidget);
    expect(find.text('165 s'), findsOneWidget);
    // Distinct answers: two short (2 and 3 days), one uncovered.
    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );
    expect(inDialog('2'), findsOneWidget);
    expect(inDialog('1'), findsOneWidget);
    expect(inDialog('0'), findsOneWidget);
    expect(inDialog('published: 1'), findsOneWidget);
    expect(inDialog('published: 0'), findsNWidgets(2));
    expect(find.text('See the 2 answers'), findsOneWidget);

    await tester.tap(find.text('See the 2 answers'));
    await tester.pumpAndSettle();
    expect(find.text('Full Body B: 26 min'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Longer rest');
    await tester.tap(find.text('Publish version 4'));
    await tester.pumpAndSettle();
    verify(
      () => repository.publish(
        RulesPublish(base: 3, rules: draft, note: 'Longer rest'),
      ),
    ).called(1);
    expect(find.text('Published version 4.'), findsOneWidget);
    expect(find.textContaining('Version 4 · published'), findsOneWidget);
    expect(find.text('Discard'), findsNothing);
  });

  testWidgets('leaving with changes asks first', (tester) async {
    final key = GlobalKey<GeneratorPageState>();
    await pumpPage(tester, key: key);
    expect(await key.currentState!.mayLeave(), isTrue);

    cubit.setValue(_rest, 165);
    await settleCheck(tester);
    final leave = key.currentState!.mayLeave();
    await tester.pumpAndSettle();
    expect(find.text('Leave without publishing?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(await leave, isFalse);
  });
}
