import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/widgets/volume_band.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/volume/domain/weekly_volume.dart';
import 'package:get_workout/features/volume/presentation/volume_cubit.dart';
import 'package:get_workout/features/volume/presentation/volume_page.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

class _VolumeCubit extends MockCubit<VolumeState> implements VolumeCubit {}

class _CatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class _ModelCubit extends MockCubit<BodyModelState> implements BodyModelCubit {}

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _EntitlementCubit extends MockCubit<EntitlementState>
    implements EntitlementCubit {}

void main() {
  final monday = CalendarDate(2026, 11, 9);
  final before = CalendarDate(2026, 11, 2);
  WeekVolume weekOf(CalendarDate start, int sets) => WeekVolume(start, [
    if (sets > 0)
      VolumeEntry(
        workoutId: 'w1',
        workoutName: 'Push',
        startedAt: start
            .addDays(4)
            .toLocalDateTime()
            .add(const Duration(hours: 18)),
        exerciseId: 'bench',
        exerciseName: 'Bench Press',
        sets: sets,
        muscles: (main: const [Muscle.pec], secondary: const []),
      ),
  ]);

  late _VolumeCubit volume;

  setUp(() {
    volume = _VolumeCubit();
    sl.registerFactoryParam<VolumeCubit, int, void>((_, _) => volume);
  });

  tearDown(sl.reset);

  Future<void> pump(
    WidgetTester tester,
    VolumeState state, {
    EntitlementState premium = const EntitlementInactive(),
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 12000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    when(() => volume.state).thenReturn(state);
    final settings = _SettingsCubit();
    when(() => settings.state)
        .thenReturn(SettingsState(UserSettings.defaultsFor(null)));
    final entitlement = _EntitlementCubit();
    when(() => entitlement.state).thenReturn(premium);
    final catalogue = _CatalogueCubit();
    when(() => catalogue.state).thenReturn(const CatalogueReady([]));
    final model = _ModelCubit();
    when(() => model.state).thenReturn(const BodyModelFailed());
    when(model.load).thenAnswer((_) async {});
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<EntitlementCubit>.value(value: entitlement),
          BlocProvider<ExerciseCatalogueCubit>.value(value: catalogue),
          BlocProvider<BodyModelCubit>.value(value: model),
        ],
        child: MaterialApp(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const VolumePage(),
        ),
      ),
    );
    await tester.pump();
  }

  VolumeState ready(List<WeekVolume> weeks, {CalendarDate? week}) =>
      VolumeState(
        week: week ?? monday,
        thisWeek: monday,
        status: VolumeStatus.ready,
        weeks: weeks,
      );

  testWidgets('the week, every muscle with the trained ones first, and a '
      'locked trend for a free user', (tester) async {
    await pump(tester, ready([weekOf(monday, 14)]));

    expect(find.text('Nov 9–15'), findsOneWidget);
    expect(find.text('Sets per muscle'), findsOneWidget);
    expect(find.text('14 total'), findsOneWidget);
    final bands = tester.widgetList<VolumeBand>(find.byType(VolumeBand));
    expect(bands.length, Muscle.values.length);
    expect(bands.first.muscle, Muscle.pec);
    expect(bands.last.sets, 0);
    final bars = tester.widgetList<BandBar>(find.byType(BandBar)).toList();
    expect(bars.first.muted, isFalse);
    expect(bars.last.muted, isTrue);
    expect(
      find.text(
        'target 10–20 per muscle · tap a muscle on the model or a bar to '
        'see its exercises',
      ),
      findsOneWidget,
    );
    expect(find.text('12-week trend'), findsOneWidget);
    expect(find.text('Total sets per week over 12 weeks.'), findsOneWidget);
  });

  testWidgets('the trend stays locked while Premium is unknown', (
    tester,
  ) async {
    await pump(
      tester,
      ready([weekOf(monday, 14)]),
      premium: const EntitlementUnknown(),
    );

    expect(find.text('Total sets per week over 12 weeks.'), findsOneWidget);
  });

  testWidgets('Premium charts each week\'s total', (tester) async {
    final weeks = [
      for (var i = trendWeeks - 1; i >= 0; i--)
        weekOf(monday.addDays(-7 * i), i == 0 ? 14 : 10),
    ];
    await pump(
      tester,
      ready(weeks),
      premium: const EntitlementActive(Entitlement(isActive: true)),
    );

    final chart = tester.widget<Chart>(
      find.ancestor(
        of: find.text('12-week trend'),
        matching: find.byType(Chart),
      ),
    );
    expect(chart.values, [for (final week in weeks) week.totalSets.toDouble()]);
    expect(chart.detail, '14 sets');
    expect(chart.startLabel, 'Aug 24');
    expect(chart.endLabel, 'Nov 9');
    expect(chart.pointLabel!(trendWeeks - 1), '14 sets · Nov 9–15');
  });

  testWidgets('a past week without sets says so, with the trend under it', (
    tester,
  ) async {
    await pump(tester, ready([weekOf(before, 0)], week: before));

    expect(find.text('Nov 2–8'), findsOneWidget);
    expect(find.text('No sets that week'), findsOneWidget);
    expect(
      find.text('Weekly sets per muscle fill in as you train.'),
      findsOneWidget,
    );
    expect(find.byType(VolumeBand), findsNothing);
    expect(find.text('12-week trend'), findsOneWidget);
  });

  testWidgets('this week without sets', (tester) async {
    await pump(tester, ready([weekOf(monday, 0)]));
    expect(find.text('No sets this week'), findsOneWidget);
  });

  testWidgets('a muscle opens its sheet; one without sets says so', (
    tester,
  ) async {
    await pump(tester, ready([weekOf(monday, 14)]));

    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();
    expect(find.byType(ForgeBottomSheet), findsOneWidget);
    expect(find.text('14 sets · 10–20 sets'), findsOneWidget);
    expect(find.text('Push · Nov 13'), findsOneWidget);
    expect(find.text('Last 12 weeks'), findsOneWidget);
    expect(
      find.text('See 12 weeks of every muscle with Premium'),
      findsOneWidget,
    );
    Navigator.of(tester.element(find.byType(ForgeBottomSheet))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calves'));
    await tester.pumpAndSettle();
    expect(find.text('0 sets · Under 10 sets'), findsOneWidget);
    expect(find.text('No sets for this muscle this week.'), findsOneWidget);
  });

  testWidgets('Premium: the sheet charts the muscle\'s weeks over the band', (
    tester,
  ) async {
    final weeks = [
      for (var i = trendWeeks - 1; i >= 0; i--)
        weekOf(monday.addDays(-7 * i), 12),
    ];
    await pump(
      tester,
      ready(weeks),
      premium: const EntitlementActive(Entitlement(isActive: true)),
    );

    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();
    final chart = tester.widget<Chart>(
      find.descendant(
        of: find.byType(ForgeBottomSheet),
        matching: find.byType(Chart),
      ),
    );
    expect(chart.title, 'Last 12 weeks');
    expect(chart.card, isFalse);
    expect(chart.band, (low: 10.0, high: 20.0));
    expect(chart.bars!.length, trendWeeks);
    expect(chart.bars!.last.label, '9');
    expect(chart.bars!.last.value, 12);
    expect(chart.bars!.last.tooltip, startsWith('12 sets · week of '));
  });

  testWidgets('a past week\'s sheet trend ends with that week', (tester) async {
    await pump(tester, ready([weekOf(before, 12)], week: before));

    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();
    expect(find.text('12 weeks to Nov 8'), findsOneWidget);
  });

  testWidgets('loading keeps the week and the card title', (tester) async {
    await pump(tester, VolumeState(week: monday, thisWeek: monday));

    expect(find.text('Nov 9–15'), findsOneWidget);
    expect(find.text('Sets per muscle'), findsOneWidget);
    expect(find.byType(VolumeBand), findsNothing);
  });

  testWidgets('a failure keeps the week over the error', (tester) async {
    when(volume.retry).thenReturn(null);
    await pump(
      tester,
      VolumeState(week: monday, thisWeek: monday, status: VolumeStatus.failure),
    );

    expect(find.text('Couldn\'t load your workouts'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    verify(volume.retry).called(1);
  });
}
