import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/l10n/app_localizations.dart';

/// Shows a component at the top of a 400 × 1600 phone page in the Slate
/// preset, with the app's texts.
Future<void> pumpComponent(WidgetTester tester, Widget child) {
  tester.view
    ..physicalSize = const Size(1200, 4800)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: AppPreset.slate.lightTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Flexible(child: child)],
        ),
      ),
    ),
  );
}
