import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/presentation/profile_questions.dart';
import 'package:get_workout/l10n/app_localizations.dart';

void main() {
  late List<EquipmentProfile> presets;
  late List<Set<Equipment>> tuned;

  Future<void> pump(WidgetTester tester, Set<Equipment>? owned) async {
    presets = [];
    tuned = [];
    tester.view
      ..physicalSize = const Size(1200, 6000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppPreset.slate.lightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: EquipmentAnswer(
              owned: owned,
              onPreset: presets.add,
              onEquipment: tuned.add,
            ),
          ),
        ),
      ),
    );
  }

  /// The selected row's index in the list, or null.
  int? selected(WidgetTester tester) =>
      tester.widget<ChoiceGrid>(find.byType(ChoiceGrid)).selected;

  testWidgets('one row per set, the matching one selected; a tap picks', (
    tester,
  ) async {
    await pump(tester, EquipmentProfile.homeGym.equipment);

    expect(find.text('Full gym'), findsOneWidget);
    expect(find.text('Resistance bands'), findsOneWidget);
    expect(find.text('Barbell'), findsNothing);
    expect(selected(tester), EquipmentProfile.homeGym.index);

    await tester.tap(find.text('Full gym'));
    await tester.pump();
    expect(presets, [EquipmentProfile.fullGym]);
    expect(selected(tester), EquipmentProfile.fullGym.index);
  });

  testWidgets('the info button opens the set as checkboxes; Done picks the '
      'tuned set, which stays selected', (tester) async {
    await pump(tester, null);

    await tester.tap(find.bySemanticsLabel('Details of Dumbbells and a bench'));
    await tester.pumpAndSettle();
    expect(
      find.text("Untick what you don't have, tick anything extra."),
      findsOneWidget,
    );
    expect(
      tester.widget<ListRow>(find.widgetWithText(ListRow, 'Dumbbell')).checked,
      isTrue,
    );
    expect(find.text('Landmine'), findsNothing);

    await tester.tap(find.text('More equipment'));
    await tester.pump();
    await tester.ensureVisible(find.text('Landmine'));
    await tester.tap(find.text('Landmine'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(tuned, [
      {Equipment.dumbbell, Equipment.bench, Equipment.landmine},
    ]);
    expect(presets, isEmpty);
    expect(selected(tester), EquipmentProfile.dumbbells.index);
  });

  testWidgets('closing the sheet without Done changes nothing', (tester) async {
    await pump(tester, EquipmentProfile.fullGym.equipment);

    await tester.tap(find.bySemanticsLabel('Details of Resistance bands'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(tuned, isEmpty);
    expect(selected(tester), EquipmentProfile.fullGym.index);
  });
}
