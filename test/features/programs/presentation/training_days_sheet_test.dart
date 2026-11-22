import 'package:material_ui/material_ui.dart';
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
    bool custom = true,
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
    if (custom) {
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
    }
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

  bool simple(WidgetTester tester) => tester
      .widget<ForgeSegmentedControl<bool>>(
        find.byType(ForgeSegmentedControl<bool>),
      )
      .selected;

  Finder weekday(String weekday) => find.descendant(
    of: find.byType(TrainingDaysSheet),
    matching: find.text(weekday),
  );

  /// The two-letter weekdays picked in Simple, in the week's order.
  List<String> pickedSimple(WidgetTester tester) => [
    for (final chip in tester.widgetList<ForgeChip>(find.byType(ForgeChip)))
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

  group('Simple', () {
    const simpleHint = 'Pick the 2 weekdays you train on.';

    testWidgets('opens when each day is on one weekday in order', (
      tester,
    ) async {
      await open(tester, custom: false);

      expect(simple(tester), isTrue);
      expect(find.text(simpleHint), findsOneWidget);
      expect(find.text(hint), findsNothing);
      expect(find.byType(SectionCard), findsNothing);
      expect(find.byType(ForgeChip), findsNWidgets(7));
      expect(pickedSimple(tester), ['Mo', 'Th']);
      expect(
        find.text('2 days a week · Tue, Wed, Fri, Sat and Sun rest'),
        findsOneWidget,
      );
      await tap(tester, find.text('Save'));
      expect(result, {1: 0, 4: 1});
    });

    testWidgets('a new program opens it with nothing picked', (tester) async {
      await open(tester, initial: const {}, custom: false);

      expect(simple(tester), isTrue);
      expect(pickedSimple(tester), isEmpty);
      expect(save(tester).onPressed, isNull);
      expect(find.textContaining('days a week'), findsNothing);
    });

    testWidgets('a schedule out of order opens Custom', (tester) async {
      await open(tester, initial: const {1: 1, 4: 0}, custom: false);

      expect(simple(tester), isFalse);
      expect(find.byType(SectionCard), findsNWidgets(2));
    });

    testWidgets('a day on two weekdays opens Custom', (tester) async {
      await open(tester, initial: const {1: 0, 2: 1, 4: 0}, custom: false);

      expect(simple(tester), isFalse);
    });

    testWidgets('Save needs exactly as many weekdays as days', (tester) async {
      await open(tester, initial: const {}, custom: false);

      await tap(tester, weekday('Fr'));
      expect(save(tester).onPressed, isNull);
      expect(
        find.text('1 day a week · Mon, Tue, Wed, Thu, Sat and Sun rest'),
        findsOneWidget,
      );
      await tap(tester, weekday('Tu'));
      expect(save(tester).onPressed, isNotNull);

      // A third weekday is not taken; a picked one turns off.
      await tap(tester, weekday('Sa'));
      expect(pickedSimple(tester), ['Tu', 'Fr']);
      await tap(tester, weekday('Tu'));
      expect(pickedSimple(tester), ['Fr']);
      expect(save(tester).onPressed, isNull);
      await tap(tester, weekday('Sa'));

      // The days go onto the weekdays in the week's order.
      await tap(tester, find.text('Save'));
      expect(result, {5: 0, 6: 1});
    });

    testWidgets('in order from the first weekday of the week', (tester) async {
      await open(
        tester,
        initial: const {},
        firstWeekday: DateTime.sunday,
        custom: false,
      );

      await tap(tester, weekday('We'));
      await tap(tester, weekday('Su'));
      await tap(tester, find.text('Save'));
      expect(result, {7: 0, 3: 1});
    });

    testWidgets('to Custom, the picked weekdays in order', (tester) async {
      await open(tester, initial: const {}, custom: false);

      await tap(tester, weekday('Fr'));
      await tap(tester, weekday('Tu'));
      await tap(tester, find.text('Custom'));

      expect(simple(tester), isFalse);
      expect(picked(tester, upperLower[0]), ['Tu']);
      expect(picked(tester, upperLower[1]), ['Fr']);
    });

    testWidgets('to Custom with too few weekdays, the first days get them', (
      tester,
    ) async {
      await open(tester, initial: const {}, custom: false);

      await tap(tester, weekday('We'));
      await tap(tester, find.text('Custom'));

      expect(picked(tester, upperLower[0]), ['We']);
      expect(picked(tester, upperLower[1]), isEmpty);
      await tap(tester, find.text('Save'));
      expect(result, {3: 0});
    });

    testWidgets('from Custom, each day on one weekday keeps the weekdays', (
      tester,
    ) async {
      await open(tester, initial: const {1: 1, 4: 0}, custom: false);

      await tap(tester, find.text('Simple'));

      expect(pickedSimple(tester), ['Mo', 'Th']);
      await tap(tester, find.text('Save'));
      expect(result, {1: 0, 4: 1});
    });

    testWidgets('from Custom, any other schedule starts empty', (tester) async {
      await open(tester);
      // Thursday moves to the first day, so it is done twice.
      await tap(tester, chip(upperLower[0], 'Th'));

      await tap(tester, find.text('Simple'));

      expect(pickedSimple(tester), isEmpty);
      expect(save(tester).onPressed, isNull);
    });

    testWidgets('back to Custom without picking, Custom is as it was', (
      tester,
    ) async {
      await open(tester, initial: const {1: 0, 2: 1, 4: 0}, custom: false);

      await tap(tester, find.text('Simple'));
      await tap(tester, find.text('Custom'));

      expect(picked(tester, upperLower[0]), ['Mo', 'Th']);
      expect(picked(tester, upperLower[1]), ['Tu']);

      await tap(tester, find.text('Simple'));
      await tap(tester, weekday('Sa'));
      await tap(tester, find.text('Custom'));
      expect(picked(tester, upperLower[0]), ['Sa']);
      expect(picked(tester, upperLower[1]), isEmpty);
    });
  });
}
