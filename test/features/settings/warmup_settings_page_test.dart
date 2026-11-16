import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/settings/presentation/warmup_settings_page.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:get_workout/l10n/app_localizations_en.dart';
import 'package:mocktail/mocktail.dart';

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

void main() {
  final l10n = AppLocalizationsEn();

  group('texts', () {
    test('each scheme says what it adds; the default says so', () {
      expect(
        [
          for (final scheme in WarmupScheme.values)
            l10n.warmupSchemeValue(scheme, const []),
        ],
        [
          'No warm-up sets',
          '1 set',
          '2 sets · default',
          '3 sets',
          'Your own sets',
        ],
      );
    });

    test('Custom shows its sets once it has some', () {
      expect(
        l10n.warmupSchemeValue(WarmupScheme.custom, const [
          WarmupStep(50, 8),
          WarmupStep(70, 5),
        ]),
        '50 % × 8 · 70 % × 5',
      );
    });

    test('the error names only the fields out of range', () {
      expect(l10n.warmupStepError(const {}), isNull);
      expect(
        l10n.warmupStepError({WarmupStepIssue.percentOutOfRange}),
        'Enter a percent from 10 to 95',
      );
      expect(
        l10n.warmupStepError({WarmupStepIssue.repsOutOfRange}),
        'Enter reps from 1 to 20',
      );
      expect(
        l10n.warmupStepError({
          WarmupStepIssue.percentOutOfRange,
          WarmupStepIssue.repsOutOfRange,
        }),
        'Enter a percent from 10 to 95 and reps from 1 to 20',
      );
    });

    test('the example lifts 80 kg, or 175 lb rounded to 5 lb', () {
      final steps = WarmupScheme.standard.presetSteps;
      expect(
        l10n.warmupExampleText(WarmupScheme.standard, WeightUnit.kg),
        'Standard · Bench Press at 80 kg',
      );
      expect(
        [
          for (final set in warmupExample(steps, WeightUnit.kg))
            l10n.warmupExampleSetText(set, WeightUnit.kg),
        ],
        ['40 kg × 8', '60 kg × 4'],
      );
      expect(
        l10n.warmupExampleText(WarmupScheme.standard, WeightUnit.lb),
        'Standard · Bench Press at 175 lb',
      );
      expect(
        [
          for (final set in warmupExample(steps, WeightUnit.lb))
            l10n.warmupExampleSetText(set, WeightUnit.lb),
        ],
        ['90 lb × 8', '130 lb × 4'],
      );
    });

    test('the summary names the scope by its new label', () {
      expect(
        l10n.warmupSettingsSummary(
          const WarmupSettings(scope: WarmupScope.firstPerMuscle),
        ),
        'Standard · First per muscle group',
      );
    });
  });

  group('page', () {
    late _SettingsCubit cubit;

    Future<void> pump(WidgetTester tester, WarmupSettings warmups) async {
      cubit = _SettingsCubit();
      when(() => cubit.state).thenReturn(
        SettingsState(
          UserSettings(
            weightUnit: WeightUnit.kg,
            lengthUnit: LengthUnit.cm,
            warmups: warmups,
          ),
        ),
      );
      when(() => cubit.update(any())).thenAnswer((_) async {});
      when(() => cubit.tipSeen(any())).thenAnswer((_) async {});
      tester.view
        ..physicalSize = const Size(1200, 4800)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider<SettingsCubit>.value(
            value: cubit,
            child: const WarmupSettingsPage(),
          ),
        ),
      );
    }

    setUpAll(() {
      registerFallbackValue(
        const UserSettings(
          weightUnit: WeightUnit.kg,
          lengthUnit: LengthUnit.cm,
        ),
      );
      registerFallbackValue(Tip.autoWarmups);
    });

    testWidgets('a preset shows its example; Off shows none', (tester) async {
      await pump(tester, const WarmupSettings());
      expect(find.text('Standard · Bench Press at 80 kg'), findsOneWidget);
      expect(find.text('40 kg × 8'), findsOneWidget);
      expect(find.text('50 %'), findsOneWidget);

      await pump(tester, const WarmupSettings(scheme: WarmupScheme.off));
      expect(find.byType(SectionCard), findsNothing);
    });

    testWidgets('the last custom set cannot be removed; five are the most', (
      tester,
    ) async {
      await pump(
        tester,
        const WarmupSettings(
          scheme: WarmupScheme.custom,
          custom: [WarmupStep(50, 8)],
        ),
      );
      await tester.tap(find.bySemanticsLabel('Remove warm-up set'));
      verifyNever(() => cubit.update(any()));

      await pump(
        tester,
        const WarmupSettings(
          scheme: WarmupScheme.custom,
          custom: [
            WarmupStep(40, 10),
            WarmupStep(55, 6),
            WarmupStep(70, 4),
            WarmupStep(80, 2),
            WarmupStep(90, 1),
          ],
        ),
      );
      expect(
        tester
            .widget<ForgeButton>(
              find.widgetWithText(ForgeButton, 'Add warm-up set'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('an invalid value shows one line and is not saved', (
      tester,
    ) async {
      await pump(
        tester,
        const WarmupSettings(
          scheme: WarmupScheme.custom,
          custom: [WarmupStep(50, 8)],
        ),
      );
      await tester.enterText(find.byType(TextField).first, '98');
      await tester.pump();
      expect(find.text('Enter a percent from 10 to 95'), findsOneWidget);
      verifyNever(() => cubit.update(any()));

      await tester.enterText(find.byType(TextField).last, '25');
      await tester.pump();
      expect(
        find.text('Enter a percent from 10 to 95 and reps from 1 to 20'),
        findsOneWidget,
      );
    });

    testWidgets('a scope is chosen with the segmented control', (tester) async {
      await pump(tester, const WarmupSettings());
      await tester.tap(find.text('First per muscle group'));
      final saved =
          verify(() => cubit.update(captureAny())).captured.single
              as UserSettings;
      expect(saved.warmups.scope, WarmupScope.firstPerMuscle);
    });
  });
}
