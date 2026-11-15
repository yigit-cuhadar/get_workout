import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/presentation/profile_questions.dart';
import 'package:get_workout/l10n/app_localizations.dart';

void main() {
  Future<List<Equipment>> pump(
    WidgetTester tester,
    Set<Equipment>? owned,
  ) async {
    final toggled = <Equipment>[];
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
              onPreset: (_) {},
              onToggle: toggled.add,
            ),
          ),
        ),
      ),
    );
    return toggled;
  }

  testWidgets('the common items, then Show all lists every item', (
    tester,
  ) async {
    await pump(tester, null);

    expect(find.text('Barbell'), findsOneWidget);
    expect(find.text('Kettlebell'), findsOneWidget);
    expect(find.text('Landmine'), findsNothing);

    await tester.tap(find.text('Show all equipment'));
    await tester.pump();
    expect(find.text('Landmine'), findsOneWidget);
    expect(find.text('Show all equipment'), findsNothing);
  });

  testWidgets('collapsed, every owned item shows too', (tester) async {
    final toggled = await pump(tester, {Equipment.barbell, Equipment.landmine});

    expect(find.text('Landmine'), findsOneWidget);
    expect(find.text('Sled'), findsNothing);
    await tester.tap(find.text('Landmine'));
    expect(toggled, [Equipment.landmine]);
  });
}
