import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/strength/domain/strength.dart';
import 'package:get_workout/features/strength/presentation/exercise_strength_cubit.dart';
import 'package:get_workout/features/strength/presentation/exercise_strength_page.dart';
import 'package:get_workout/features/strength/presentation/strength_list_cubit.dart';
import 'package:get_workout/features/strength/presentation/strength_list_page.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';

import '../programs/fixtures.dart';

class _ListCubit extends MockCubit<StrengthListState>
    implements StrengthListCubit {}

class _StrengthCubit extends MockCubit<ExerciseStrengthState>
    implements ExerciseStrengthCubit {}

class _CatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _EntitlementCubit extends MockCubit<EntitlementState>
    implements EntitlementCubit {}

String path(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  final year = DateTime.now().year;
  final bench = move('bench', name: 'Bench Press');
  final plank = move('plank', name: 'Plank', type: LoggingType.duration);
  final friday = DateTime(year, 11, 13, 18);
  final lastYear = DateTime(year - 1, 9, 3, 18);

  late _ListCubit list;
  late _StrengthCubit strength;
  late _CatalogueCubit catalogue;

  setUp(() {
    list = _ListCubit();
    strength = _StrengthCubit();
    catalogue = _CatalogueCubit();
    when(() => catalogue.state).thenReturn(CatalogueReady([bench, plank]));
    when(() => list.setLanguage(any())).thenReturn(null);
    when(() => list.setQuery(any())).thenReturn(null);
    sl
      ..registerFactory<StrengthListCubit>(() => list)
      ..registerFactoryParam<ExerciseStrengthCubit, String, WeightUnit>(
        (_, _) => strength,
      );
  });

  tearDown(sl.reset);

  /// [location] in a router with the strength pages; any other route shows
  /// its path.
  Future<GoRouter> pump(
    WidgetTester tester,
    String location, {
    EntitlementState premium = const EntitlementInactive(),
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 4800)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final settings = _SettingsCubit();
    when(() => settings.state)
        .thenReturn(SettingsState(UserSettings.defaultsFor(null)));
    final entitlement = _EntitlementCubit();
    when(() => entitlement.state).thenReturn(premium);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/progress/strength',
          builder: (_, _) => const StrengthListPage(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, state) =>
                  ExerciseStrengthPage(exerciseId: state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: '/:a/:b/:c',
          builder: (_, state) => Text('at ${state.uri.path}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<EntitlementCubit>.value(value: entitlement),
          BlocProvider<ExerciseCatalogueCubit>.value(value: catalogue),
        ],
        child: MaterialApp.router(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    return router;
  }

  group('Strength list', () {
    testWidgets('rows with the last day done, the year only for another '
        'one, and a removed exercise', (tester) async {
      when(() => list.state).thenReturn(
        StrengthListState(
          status: StrengthListStatus.ready,
          trainedCount: 2,
          items: [
            StrengthItem(
              exerciseId: 'bench',
              lastTrained: friday,
              exercise: bench,
            ),
            StrengthItem(
              exerciseId: 'gone',
              lastTrained: lastYear,
              removed: true,
            ),
          ],
        ),
      );
      await pump(tester, '/progress/strength');

      expect(find.byType(ForgeSearchField), findsOneWidget);
      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('Last done Nov 13'), findsOneWidget);
      expect(find.text('Exercise no longer in your library'), findsOneWidget);
      expect(find.text('Last done Sep 3, ${year - 1}'), findsOneWidget);
      final rows = tester.widgetList<ListRow>(find.byType(ListRow)).toList();
      expect([for (final row in rows) row.muted], [false, true]);
    });

    testWidgets('nothing yet: one line and no search', (tester) async {
      when(
        () => list.state,
      ).thenReturn(const StrengthListState(status: StrengthListStatus.ready));
      await pump(tester, '/progress/strength');

      expect(
        find.text('Finish a workout to see your records and progress here.'),
        findsOneWidget,
      );
      expect(find.byType(ForgeSearchField), findsNothing);
    });

    testWidgets('no match: one line under the search', (tester) async {
      when(() => list.state).thenReturn(
        const StrengthListState(
          status: StrengthListStatus.ready,
          trainedCount: 2,
          query: 'benchh',
        ),
      );
      await pump(tester, '/progress/strength');

      expect(find.text('No exercises match your search.'), findsOneWidget);
      expect(find.byType(ForgeSearchField), findsOneWidget);
    });

    testWidgets('loading shows shimmering rows', (tester) async {
      when(() => list.state).thenReturn(const StrengthListState());
      await pump(tester, '/progress/strength');

      expect(find.byType(ListRow), findsNWidgets(6));
    });
  });

  group('Strength', () {
    const set = (weightKg: 82.5, reps: 8, durationS: null);
    final session = HistoryPoint(
      date: friday,
      workoutId: 'w1',
      bestE1rmKg: 104.5,
      bestSet: set,
      workoutName: 'Push',
    );
    StatRecord record(double value) =>
        StatRecord(value: value, date: friday, workoutId: 'w1', set: set);
    final ready = ExerciseStrengthState(
      status: ExerciseStrengthStatus.ready,
      trained: true,
      charted: true,
      records: [
        (kind: RecordKind.bestE1rm, record: record(104.5)),
        (kind: RecordKind.heaviestWeight, record: record(82.5)),
      ],
      points: [(date: friday, value: 104.5, workoutId: 'w1')],
      sessions: [session],
      rangeStart: DateTime(year, 8, 24),
      olderLocked: true,
      loggingType: LoggingType.weightReps,
    );

    testWidgets('the exercise row, the chart, records and sessions', (
      tester,
    ) async {
      when(() => strength.state).thenReturn(ready);
      await pump(tester, '/progress/strength/bench');

      expect(find.text('Strength'), findsOneWidget);
      expect(find.text('Exercise'), findsOneWidget);
      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.byType(ForgeSegmentedControl<StrengthRange>), findsOneWidget);
      expect(find.text('Estimated 1RM'), findsOneWidget);
      expect(find.text('Aug 24 – Nov 13'), findsOneWidget);
      expect(
        find.text(
          'Your results from before the last 2 weeks are part of Premium.',
        ),
        findsOneWidget,
      );
      expect(find.text('Best e1RM'), findsOneWidget);
      expect(find.text('104.5 kg'), findsOneWidget);
      expect(find.text('Heaviest'), findsOneWidget);
      expect(find.text('82.5 kg × 8'), findsOneWidget);
      expect(find.text('Fri, Nov 13'), findsNWidgets(2));
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('82.5 × 8 · e1RM 104.5'), findsOneWidget);
      expect(find.text('Fri, Nov 13 · Push'), findsOneWidget);
      ListRow row(String text) => tester.widget<ListRow>(
        find.ancestor(of: find.text(text), matching: find.byType(ListRow)),
      );
      expect(row('82.5 × 8 · e1RM 104.5').dataTitle, isTrue);
      expect(row('Heaviest').dataValue, isTrue);
    });

    testWidgets('only a session opens its workout', (tester) async {
      when(() => strength.state).thenReturn(ready);
      final router = await pump(tester, '/progress/strength/bench');

      await tester.tap(find.text('Heaviest'));
      await tester.pumpAndSettle();
      expect(path(router), '/progress/strength/bench');

      await tester.tap(find.text('82.5 × 8 · e1RM 104.5'));
      await tester.pumpAndSettle();
      expect(find.text('at /progress/calendar/w1'), findsOneWidget);
    });

    testWidgets('no e1RM in the range: the empty chart', (tester) async {
      when(() => strength.state).thenReturn(
        ExerciseStrengthState(
          status: ExerciseStrengthStatus.ready,
          trained: true,
          charted: true,
          records: ready.records,
          rangeStart: DateTime(year, 8, 24),
          loggingType: LoggingType.weightReps,
        ),
      );
      await pump(tester, '/progress/strength/bench');

      expect(find.text('No estimated 1RM in these 2 weeks'), findsOneWidget);
      final today = DateFormat.MMMd('en').format(DateTime.now());
      expect(find.text('Aug 24 – $today'), findsOneWidget);
      expect(
        find.text('Log a set of Bench Press to continue the line.'),
        findsOneWidget,
      );
      expect(find.text('Sessions'), findsNothing);
    });

    testWidgets('a timed exercise: no chart, its time and every session', (
      tester,
    ) async {
      const held = (weightKg: null, reps: null, durationS: 105);
      when(() => strength.state).thenReturn(
        ExerciseStrengthState(
          status: ExerciseStrengthStatus.ready,
          trained: true,
          records: [
            (
              kind: RecordKind.longestDuration,
              record: StatRecord(
                value: 105,
                date: friday,
                workoutId: 'w1',
                set: held,
              ),
            ),
          ],
          sessions: [
            HistoryPoint(
              date: friday,
              workoutId: 'w1',
              bestSet: held,
              workoutName: 'Legs',
            ),
          ],
          loggingType: LoggingType.duration,
        ),
      );
      await pump(tester, '/progress/strength/plank');

      expect(find.byType(ForgeSegmentedControl<StrengthRange>), findsNothing);
      expect(find.text('Longest time'), findsOneWidget);
      expect(find.text('1:45'), findsNWidgets(2));
      expect(find.text('Fri, Nov 13 · Legs'), findsOneWidget);
    });

    testWidgets('not done yet names the exercise', (tester) async {
      when(() => strength.state).thenReturn(
        const ExerciseStrengthState(status: ExerciseStrengthStatus.ready),
      );
      await pump(tester, '/progress/strength/bench');

      expect(find.text('No sessions of Bench Press yet'), findsOneWidget);
      expect(
        find.text('Your estimated 1RM appears after the first logged set.'),
        findsOneWidget,
      );
    });

    testWidgets('a removed exercise says so in its row', (tester) async {
      when(() => strength.state).thenReturn(
        const ExerciseStrengthState(status: ExerciseStrengthStatus.ready),
      );
      await pump(tester, '/progress/strength/gone');

      expect(find.text('Exercise no longer in your library'), findsOneWidget);
      expect(find.text('No sessions yet'), findsOneWidget);
    });

    testWidgets('the Exercise row opens radio rows with this one picked, '
        'and another exercise replaces the page', (tester) async {
      when(() => strength.state).thenReturn(ready);
      when(() => list.state).thenReturn(
        StrengthListState(
          status: StrengthListStatus.ready,
          trainedCount: 2,
          items: [
            StrengthItem(
              exerciseId: 'bench',
              lastTrained: friday,
              exercise: bench,
            ),
            StrengthItem(
              exerciseId: 'plank',
              lastTrained: friday,
              exercise: plank,
            ),
            StrengthItem(
              exerciseId: 'gone',
              lastTrained: lastYear,
              removed: true,
            ),
          ],
        ),
      );
      final router = await pump(tester, '/progress/strength/bench');

      await tester.tap(find.text('Exercise'));
      await tester.pumpAndSettle();
      final sheet = find.byType(ForgeBottomSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.byType(ForgeSearchField)),
        findsOneWidget,
      );
      final grid = tester.widget<ChoiceGrid>(
        find.descendant(of: sheet, matching: find.byType(ChoiceGrid)),
      );
      expect(grid.selected, 0);
      expect(grid.form, ChoiceListForm.stacked);
      // A removed exercise is a normal row, its last day as the hint.
      expect(
        [for (final option in grid.options) (option.label, option.hint)],
        [
          ('Bench Press', 'Last done Nov 13'),
          ('Plank', 'Last done Nov 13'),
          (
            'Exercise no longer in your library',
            'Last done Sep 3, ${year - 1}',
          ),
        ],
      );
      expect([for (final o in grid.options) o.enabled], [true, true, true]);

      await tester.tap(
        find.descendant(of: sheet, matching: find.text('Plank')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ForgeBottomSheet), findsNothing);
      expect(path(router), '/progress/strength/plank');
    });

    testWidgets('loading keeps the row and the chart title', (tester) async {
      when(() => strength.state).thenReturn(const ExerciseStrengthState());
      await pump(tester, '/progress/strength/bench');

      expect(find.text('Exercise'), findsOneWidget);
      expect(find.text('Estimated 1RM'), findsOneWidget);
    });

    testWidgets('a load failure keeps the row over the error', (tester) async {
      when(() => strength.state).thenReturn(
        const ExerciseStrengthState(status: ExerciseStrengthStatus.failure),
      );
      when(strength.retry).thenReturn(null);
      await pump(tester, '/progress/strength/bench');

      expect(find.text('Couldn\'t load your progress'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      verify(strength.retry).called(1);
    });
  });
}
