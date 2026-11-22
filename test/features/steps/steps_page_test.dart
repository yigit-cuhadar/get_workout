import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/steps/domain/steps.dart';
import 'package:get_workout/features/steps/presentation/steps_cubit.dart';
import 'package:get_workout/features/steps/presentation/steps_page.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

class _MockSteps extends MockCubit<StepsState> implements StepsCubit {}

class _MockSettings extends MockCubit<SettingsState> implements SettingsCubit {}

class _FakeSettings extends Fake implements UserSettings {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeSettings()));

  late _MockSteps steps;
  late _MockSettings settings;

  StepsHistory history(int today, {int before = 8000}) {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return StepsHistory([
      for (var i = stepHistoryDays - 1; i > 0; i--)
        DailySteps(day.subtract(Duration(days: i)), before),
      DailySteps(day, today),
    ]);
  }

  Future<void> pump(WidgetTester tester, StepsState state) async {
    tester.view
      ..physicalSize = const Size(1200, 2600)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    steps = _MockSteps();
    whenListen(steps, const Stream<StepsState>.empty(), initialState: state);
    when(steps.load).thenAnswer((_) async {});
    when(steps.allow).thenAnswer((_) async {});
    when(steps.openSettings).thenAnswer((_) async => true);
    sl.registerFactory<StepsCubit>(() => steps);
    settings = _MockSettings();
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: const SettingsState(
        UserSettings(weightUnit: WeightUnit.kg, lengthUnit: LengthUnit.cm),
        loaded: true,
      ),
    );
    when(() => settings.update(any())).thenAnswer((_) async {});
    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: settings,
        child: MaterialApp(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const StepsPage(),
        ),
      ),
    );
    await tester.pump();
  }

  tearDown(sl.reset);

  testWidgets('shows today in the ring and what is left', (tester) async {
    await pump(
      tester,
      StepsState(access: StepsAccess.granted, history: history(6240)),
    );
    expect(find.text('6,240'), findsOneWidget);
    expect(find.text('of 10,000'), findsOneWidget);
    expect(find.text('3,760 to go'), findsOneWidget);
    expect(find.text('daily goal'), findsOneWidget);
    expect(find.text('This week'), findsWidgets);
    // Holding a day's bar names its steps and date.
    final chart = tester.widget<Chart>(find.byType(Chart));
    final today = chart.bars![chart.current!];
    expect(today.tooltip, startsWith('6,240 steps · '));
  });

  testWidgets('says the goal is reached', (tester) async {
    await pump(
      tester,
      StepsState(access: StepsAccess.granted, history: history(10480)),
    );
    expect(find.text('Goal reached'), findsWidgets);
  });

  testWidgets('plus raises the goal by 100 and saves it', (tester) async {
    await pump(
      tester,
      StepsState(access: StepsAccess.granted, history: history(500)),
    );
    await tester.tap(find.byType(StepperField));
    final plus = find.descendant(
      of: find.byType(StepperField),
      matching: find.byType(GestureDetector),
    );
    await tester.tap(plus.last);
    await tester.pump();
    final saved =
        verify(() => settings.update(captureAny())).captured.last
            as UserSettings;
    expect(saved.stepGoal, 10100);
  });

  testWidgets('an all-zero iOS history says where to allow access', (
    tester,
  ) async {
    await pump(
      tester,
      StepsState(
        access: StepsAccess.undetermined,
        history: history(0, before: 0),
      ),
    );
    expect(find.text('No steps showing?'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    verify(steps.openSettings).called(1);
  });

  testWidgets('explains before asking, then asks', (tester) async {
    await pump(tester, const StepsState(access: StepsAccess.explain));
    expect(find.text('See your steps here'), findsOneWidget);
    await tester.tap(find.text('Allow access'));
    verify(steps.allow).called(1);
  });

  testWidgets('a failed request offers a retry', (tester) async {
    await pump(
      tester,
      const StepsState(
        access: StepsAccess.explain,
        failure: UnknownFailure('x'),
      ),
    );
    expect(
      find.text('Something went wrong. Try again in a moment.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    verify(steps.allow).called(1);
  });

  testWidgets('a refusal on Android opens Health Connect or asks again', (
    tester,
  ) async {
    await pump(tester, const StepsState(access: StepsAccess.denied));
    expect(find.text('Access is off'), findsOneWidget);
    await tester.tap(find.text('Ask again'));
    verify(steps.allow).called(1);
    await tester.tap(find.text('Open Health Connect'));
    verify(steps.openSettings).called(1);
  });

  testWidgets('a missing Health Connect offers its store page', (tester) async {
    await pump(tester, const StepsState(access: StepsAccess.notInstalled));
    expect(find.text('Health Connect is needed'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    await tester.tap(find.text('Get Health Connect'));
    verify(steps.openSettings).called(1);
  });

  testWidgets('a device with no health store says so in one line', (
    tester,
  ) async {
    await pump(tester, const StepsState(access: StepsAccess.unsupported));
    expect(
      find.text(
        'Steps come from Apple Health or Health Connect, and this device '
        'has neither.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a load failure offers a retry', (tester) async {
    await pump(tester, const StepsState(failure: UnknownFailure('x')));
    expect(find.text("Couldn't read your steps"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    verify(steps.load).called(greaterThan(1));
  });

  testWidgets('loads with skeletons', (tester) async {
    await pump(tester, const StepsState());
    expect(find.byType(SkeletonBar), findsWidgets);
  });
}
