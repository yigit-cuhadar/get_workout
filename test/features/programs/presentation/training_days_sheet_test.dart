import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/programs/presentation/training_days_sheet.dart';
import 'package:get_workout/l10n/app_localizations.dart';

void main() {
  const upperLower = ['Upper Body Strength A', 'Lower Body Hypertrophy B'];
  const hint = 'Tap the weekdays each day is done on; a weekday holds one day.';

  late Map<int, int>? result;
  late bool closed;

  /// Opens the sheet on a 390 × 844 phone and keeps what it returns.
  Future<void> open(
    WidgetTester tester, {
    List<String> dayNames = upperLower,
    Map<int, int> initial = const {1: 0, 4: 1},
    int firstWeekday = DateTime.monday,
    double textScale = 1,
  }) async {
    result = null;
    closed = false;
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppPreset.slate.lightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                result = await showForgeBottomSheet<Map<int, int>>(
                  context: context,
                  builder: (_) => TrainingDaysSheet(
                    dayNames: dayNames,
                    initial: initial,
                    firstWeekday: firstWeekday,
                    confirmLabel: 'Save',
                  ),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder card(String day) => find.widgetWithText(SectionCard, day);

  Finder chip(String day, String weekday) =>
      find.descendant(of: card(day), matching: find.text(weekday));

  /// The two-letter weekdays picked on [day]'s card, in its order.
  List<String> picked(WidgetTester tester, String day) => [
    for (final chip in tester.widgetList<ForgeChip>(
      find.descendant(of: card(day), matching: find.byType(ForgeChip)),
    ))
      if (chip.selected) chip.label,
  ];

  ForgeButton save(WidgetTester tester) =>
      tester.widget<ForgeButton>(find.widgetWithText(ForgeButton, 'Save'));

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Map<int, int> everyWeekday(int Function(int weekday) dayOf) => {
    for (var weekday = 1; weekday <= 7; weekday++) weekday: dayOf(weekday),
  };

  testWidgets('a card per day with its weekdays, the hint and a summary', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Training days'), findsOneWidget);
    expect(find.text(hint), findsOneWidget);
    expect(find.byType(SectionCard), findsNWidgets(2));
    expect(find.byType(ForgeChip), findsNWidgets(14));
    expect(picked(tester, upperLower[0]), ['Mo']);
    expect(picked(tester, upperLower[1]), ['Th']);
    expect(
      find.text('2 days a week · Tue, Wed, Fri, Sat and Sun rest'),
      findsOneWidget,
    );
  });

  testWidgets('a day done on several weekdays; Save returns the schedule', (
    tester,
  ) async {
    await open(tester);

    await tap(tester, chip(upperLower[1], 'Tu'));
    await tap(tester, chip(upperLower[0], 'Th'));
    await tap(tester, chip(upperLower[1], 'Fr'));

    expect(picked(tester, upperLower[0]), ['Mo', 'Th']);
    expect(picked(tester, upperLower[1]), ['Tu', 'Fr']);
    expect(find.text('4 days a week · Wed, Sat and Sun rest'), findsOneWidget);
    await tap(tester, find.text('Save'));
    expect(closed, isTrue);
    expect(result, {1: 0, 2: 1, 4: 0, 5: 1});
  });

  testWidgets('a weekday picked for another day moves to it', (tester) async {
    await open(tester);

    await tap(tester, chip(upperLower[1], 'Mo'));

    expect(picked(tester, upperLower[0]), isEmpty);
    expect(picked(tester, upperLower[1]), ['Mo', 'Th']);
    await tap(tester, find.text('Save'));
    expect(result, {1: 1, 4: 1});
  });

  testWidgets('a picked weekday turns off again', (tester) async {
    await open(tester);

    await tap(tester, chip(upperLower[0], 'Mo'));

    expect(picked(tester, upperLower[0]), isEmpty);
    expect(
      find.text('1 day a week · Mon, Tue, Wed, Fri, Sat and Sun rest'),
      findsOneWidget,
    );
  });

  testWidgets('Save needs a weekday; Cancel returns nothing', (tester) async {
    await open(tester);

    await tap(tester, chip(upperLower[0], 'Mo'));
    await tap(tester, chip(upperLower[1], 'Th'));
    expect(save(tester).onPressed, isNull);
    expect(find.textContaining('days a week'), findsNothing);

    await tap(tester, find.text('Cancel'));
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('every weekday trained has no rest part', (tester) async {
    await open(tester, initial: everyWeekday((_) => 0));

    expect(find.text('7 days a week'), findsOneWidget);
  });

  testWidgets('the week starts on the first weekday given', (tester) async {
    await open(tester, firstWeekday: DateTime.sunday);

    final chips = tester.widgetList<ForgeChip>(
      find.descendant(
        of: card(upperLower[0]),
        matching: find.byType(ForgeChip),
      ),
    );
    expect(
      [for (final chip in chips) chip.label],
      ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'],
    );
    expect(
      find.text('2 days a week · Sun, Tue, Wed, Fri and Sat rest'),
      findsOneWidget,
    );
  });

  testWidgets('a chip reads out its full weekday', (tester) async {
    await open(tester);

    expect(
      find.descendant(
        of: card(upperLower[0]),
        matching: find.bySemanticsLabel('Monday'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('days a program no longer has fall back inside it', (
    tester,
  ) async {
    await open(tester, initial: const {1: 0, 4: 3});

    expect(picked(tester, upperLower[1]), ['Th']);
    await tap(tester, find.text('Save'));
    expect(result, {1: 0, 4: 1});
  });

  testWidgets('seven long day names show whole on a phone', (tester) async {
    final names = [
      for (var i = 1; i <= 7; i++)
        'Day $i · Heavy compound strength and accessory volume work',
    ];
    await open(
      tester,
      dayNames: names,
      initial: everyWeekday((weekday) => weekday - 1),
    );

    expect(tester.takeException(), isNull);
    for (final name in names) {
      expect(find.text(name), findsOneWidget);
    }
    // The last card is reached by scrolling and still picks.
    await tap(tester, chip(names.last, 'Mo'));
    expect(picked(tester, names.last), ['Mo', 'Su']);
    expect(picked(tester, names.first), isEmpty);
  });

  testWidgets('with large text the sheet scrolls; the actions stay', (
    tester,
  ) async {
    await open(
      tester,
      dayNames: [for (var i = 1; i <= 7; i++) 'Day $i'],
      initial: everyWeekday((weekday) => weekday - 1),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    final scroll = find.descendant(
      of: find.byType(TrainingDaysSheet),
      matching: find.byType(Scrollable),
    );
    expect(scroll, findsOneWidget);
    expect(
      tester.state<ScrollableState>(scroll).position.maxScrollExtent,
      greaterThan(0),
    );
    await tap(tester, chip('Day 7', 'Mo'));
    expect(find.text('Save'), findsOneWidget);
    await tap(tester, find.text('Save'));
    expect(result, {1: 6, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6});
  });
}
