import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/l10n/app_localizations.dart';

/// Shows [child] alone on a page in the shipped preset's light theme.
Future<void> pumpComponent(WidgetTester tester, Widget child) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppPreset.shipped.lightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
