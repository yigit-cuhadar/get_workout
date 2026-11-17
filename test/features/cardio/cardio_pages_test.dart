import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/unsaved_changes.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/cardio/domain/cardio_week.dart';
import 'package:get_workout/features/cardio/presentation/cardio_form_cubit.dart';
import 'package:get_workout/features/cardio/presentation/cardio_form_page.dart';
import 'package:get_workout/features/cardio/presentation/cardio_list_cubit.dart';
import 'package:get_workout/features/cardio/presentation/cardio_list_page.dart';
import 'package:get_workout/features/cardio/presentation/cardio_session_page.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockList extends MockCubit<CardioListState> implements CardioListCubit {}

class _MockForm extends MockCubit<CardioFormState> implements CardioFormCubit {}

class _MockSettings extends MockCubit<SettingsState> implements SettingsCubit {}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 7, 30);
  final run = CardioSession(
    id: 'r1',
    type: CardioType.outdoorRun,
    date: today,
    duration: const Duration(minutes: 28, seconds: 40),
    distanceKm: 5.2,
    calories: 310,
    note: 'Easy pace, felt good',
  );
  final ride = CardioSession(
    id: 'health-x',
    type: CardioType.outdoorCycle,
    date: today.subtract(const Duration(hours: 1)),
    duration: const Duration(minutes: 45),
    distanceKm: 18,
    avgHeartRate: 142,
    healthSource: 'com.strava',
  );
  final bike = CardioSession(
    id: 'b1',
    type: CardioType.elliptical,
    date: today.subtract(const Duration(hours: 2)),
    duration: const Duration(minutes: 30),
  );

  late _MockList list;

  CardioListState ready(List<CardioSession> sessions) => CardioListState(
    status: CardioListStatus.ready,
    sessions: sessions,
    weeks: groupByWeek(sessions, DateTime.monday),
    chart: lastWeeks(sessions, DateTime.monday, now: now),
  );

  Future<void> pump(WidgetTester tester, CardioListState state, Widget page) {
    tester.view
      ..physicalSize = const Size(1200, 2600)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    list = _MockList();
    whenListen(
      list,
      const Stream<CardioListState>.empty(),
      initialState: state,
    );
    when(() => list.firstWeekday).thenReturn(DateTime.monday);
    when(list.refreshNow).thenReturn(null);
    sl.registerSingleton<CardioListCubit>(list);
    final settings = _MockSettings();
    when(() => settings.state).thenReturn(
      const SettingsState(
        UserSettings(weightUnit: WeightUnit.kg, lengthUnit: LengthUnit.cm),
        loaded: true,
      ),
    );
    return tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: settings,
        child: MaterialApp(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: page,
        ),
      ),
    );
  }

  tearDown(sl.reset);

  group('list', () {
    testWidgets('the week in a band, the chart and the sessions', (
      tester,
    ) async {
      await pump(tester, ready([run, ride]), const CardioListPage());
      expect(find.text('23.2 km · 74 min'), findsOneWidget);
      expect(find.text('2 sessions'), findsOneWidget);
      expect(find.text('12 weeks'), findsOneWidget);
      final chart = tester.widget<Chart>(find.byType(Chart));
      expect(chart.smallLabels, isTrue);
      final labels = [for (final bar in chart.bars!) bar.label];
      expect(labels.last, DateFormat.MMMd().format(weekStart(now, 1)));
      expect(labels[labels.length - 2], isEmpty);
      // Weeks without minutes keep their bar and show no figure.
      expect(chart.bars!.first.value, 0);
      expect(chart.bars!.first.valueLabel, isNull);
      expect(chart.bars!.last.valueLabel, '74');
      expect(find.text('Outdoor run · 5.2 km'), findsOneWidget);
      expect(find.text('Strava'), findsOneWidget);
      expect(find.text('Log cardio'), findsOneWidget);
    });

    testWidgets('a week without distance reads its minutes', (tester) async {
      await pump(tester, ready([bike]), const CardioListPage());
      expect(find.text('30 min'), findsWidgets);
      expect(find.text('Elliptical'), findsOneWidget);
    });

    testWidgets('no session: a zero band, the message and Log cardio', (
      tester,
    ) async {
      await pump(tester, ready(const []), const CardioListPage());
      expect(find.text('0 km · 0 min'), findsOneWidget);
      expect(find.text('No sessions yet'), findsOneWidget);
      expect(find.text('No cardio logged'), findsOneWidget);
      expect(find.text('12 weeks'), findsNothing);
      expect(find.text('Log cardio'), findsOneWidget);
    });

    testWidgets('a load failure offers a retry, no Log cardio', (tester) async {
      await pump(
        tester,
        const CardioListState(
          status: CardioListStatus.failure,
          failure: NetworkFailure(),
        ),
        const CardioListPage(),
      );
      expect(find.text("Couldn't load your cardio"), findsOneWidget);
      expect(find.text('Log cardio'), findsNothing);
    });
  });

  group('session', () {
    testWidgets('tiles, the rows it has, Edit and Delete', (tester) async {
      await pump(tester, ready([run]), const CardioSessionPage(id: 'r1'));
      expect(find.text('5.2 km'), findsOneWidget);
      expect(find.text('28:40'), findsOneWidget);
      expect(find.text('5:31'), findsOneWidget);
      expect(find.text('per km'), findsOneWidget);
      expect(find.text('310 kcal'), findsOneWidget);
      expect(find.text('Easy pace, felt good'), findsOneWidget);
      expect(find.text('Average heart rate'), findsNothing);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('one from the health store says where to change it', (
      tester,
    ) async {
      await pump(
        tester,
        ready([ride]),
        const CardioSessionPage(id: 'health-x'),
      );
      expect(
        find.text('From Health Connect. Change it there.'),
        findsOneWidget,
      );
      expect(find.text('km/h'), findsOneWidget);
      expect(find.text('142 bpm'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('without a distance only the time', (tester) async {
      await pump(tester, ready([bike]), const CardioSessionPage(id: 'b1'));
      expect(find.text('time'), findsOneWidget);
      expect(find.text('distance'), findsNothing);
    });

    testWidgets('Delete asks first, then deletes', (tester) async {
      final form = _MockForm();
      whenListen(
        form,
        const Stream<CardioFormState>.empty(),
        initialState: CardioFormState(
          type: CardioType.outdoorRun,
          date: today,
          status: CardioFormStatus.deleted,
        ),
      );
      when(form.delete).thenAnswer((_) async {});
      await pump(tester, ready([run]), const CardioSessionPage(id: 'r1'));
      sl.registerFactoryParam<CardioFormCubit, CardioSession?, DistanceUnit>(
        (_, _) => form,
      );
      await tester.tap(find.widgetWithText(ForgeButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this session?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ForgeButton, 'Delete').last);
      await tester.pumpAndSettle();
      verify(form.delete).called(1);
    });

    testWidgets('a session gone shows one line', (tester) async {
      await pump(tester, ready([run]), const CardioSessionPage(id: 'nope'));
      expect(find.text('This session no longer exists.'), findsOneWidget);
    });
  });

  group('form', () {
    late _MockForm form;

    Future<void> showForm(
      WidgetTester tester,
      CardioFormState state, {
      CardioSession? session,
    }) async {
      form = _MockForm();
      whenListen(
        form,
        const Stream<CardioFormState>.empty(),
        initialState: state,
      );
      when(() => form.isEditing).thenReturn(session != null);
      when(() => form.session).thenReturn(
        CardioSession(
          type: state.type,
          date: state.date,
          duration: state.duration,
          distanceKm: state.distance,
        ),
      );
      when(form.save).thenAnswer((_) async {});
      when(() => form.hasChanges).thenReturn(false);
      // A fresh form for each call.
      await tester.pumpWidget(const SizedBox());
      await sl.reset();
      sl.registerFactoryParam<CardioFormCubit, CardioSession?, DistanceUnit>(
        (_, _) => form,
      );
      tester.view
        ..physicalSize = const Size(1200, 2600)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final list = _MockList();
      whenListen(
        list,
        const Stream<CardioListState>.empty(),
        initialState: ready([?session]),
      );
      sl.registerSingleton<CardioListCubit>(list);
      final settings = _MockSettings();
      when(() => settings.state).thenReturn(
        const SettingsState(
          UserSettings(weightUnit: WeightUnit.kg, lengthUnit: LengthUnit.cm),
          loaded: true,
        ),
      );
      final unsaved = UnsavedChanges();
      final router = GoRouter(
        initialLocation: '/form',
        onEnter: unsaved.onEnter,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Text('the list'),
            routes: [
              GoRoute(
                path: 'form',
                builder: (_, _) => session == null
                    ? const CardioNewPage()
                    : CardioEditPage(id: session.id!),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        RepositoryProvider.value(
          value: unsaved,
          child: BlocProvider<SettingsCubit>.value(
            value: settings,
            child: MaterialApp.router(
              theme: AppPreset.slate.lightTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a row per value with its picker; Save faded and Duration '
        'missing while there is no duration', (tester) async {
      await showForm(
        tester,
        CardioFormState(type: CardioType.outdoorRun, date: today),
      );

      final rows = tester.widgetList<ListRow>(find.byType(ListRow)).toList();
      expect(rows.map((row) => row.title), [
        'Type',
        'Date and time',
        'Duration',
        'Distance',
        'Calories',
        'Average heart rate',
        'Note',
      ]);
      expect(rows[1].value, startsWith('Today, '));
      expect((rows[2].missing, rows[2].value), (true, '—'));
      expect(rows[2].error, 'Enter a duration');
      expect(rows.every((row) => row.end == ListRowEnd.chevron), isTrue);
      final save = tester
          .widgetList<ForgeAppBarAction>(find.byType(ForgeAppBarAction))
          .singleWhere((action) => action.label == 'Save');
      expect(save.onPressed, isNull);
      expect(find.textContaining('Pace'), findsNothing);
    });

    testWidgets('values, the pace under the rows, Save on; no delete', (
      tester,
    ) async {
      await showForm(
        tester,
        CardioFormState(
          type: CardioType.outdoorRun,
          date: run.date,
          duration: run.duration,
          distance: 5.2,
          calories: 310,
          note: 'Easy pace, felt good',
        ),
        session: run,
      );

      expect(find.text('Edit cardio'), findsOneWidget);
      expect(find.text('28:40'), findsOneWidget);
      expect(find.text('5.2 km'), findsOneWidget);
      expect(find.text('310 kcal'), findsOneWidget);
      expect(find.text('Pace 5:31 /km'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete'), findsNothing);

      await tester.tap(find.text('Save'));
      verify(form.save).called(1);
    });

    testWidgets('speed types read a speed; incline types add incline, '
        'no-distance types drop distance', (tester) async {
      await showForm(
        tester,
        CardioFormState(
          type: CardioType.outdoorCycle,
          date: today,
          duration: const Duration(hours: 1),
          distance: 22.4,
        ),
      );
      expect(find.text('Speed 22.4 km/h'), findsOneWidget);

      await showForm(
        tester,
        CardioFormState(type: CardioType.stairClimber, date: today),
      );
      expect(find.text('Distance'), findsNothing);
      expect(find.text('Incline'), findsOneWidget);
    });

    testWidgets('Duration opens the h:m:s wheel; Distance a typed number '
        'sheet that keeps a value out of range', (tester) async {
      await showForm(
        tester,
        CardioFormState(type: CardioType.outdoorRun, date: today),
      );

      await tester.tap(find.text('Duration'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgeDurationWheel), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Distance'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgeBottomSheet), findsOneWidget);
      // Titled and labelled with the name; the unit sits in the box.
      expect(find.text('Distance'), findsNWidgets(3));
      expect(
        tester.widget<ForgeTextField>(find.byType(ForgeTextField)).unit,
        'km',
      );
      // No value yet: no Clear.
      expect(find.text('Clear'), findsNothing);

      await tester.enterText(find.byType(TextField), '900');
      await tester.tap(find.widgetWithText(ForgeButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a distance from 0.01 to 500 km (310 mi)'),
        findsOneWidget,
      );
      verifyNever(() => form.setDistance(any()));

      await tester.enterText(find.byType(TextField), '5,2');
      await tester.tap(find.widgetWithText(ForgeButton, 'Save'));
      await tester.pumpAndSettle();
      verify(() => form.setDistance(5.2)).called(1);
      expect(find.byType(ForgeBottomSheet), findsNothing);
    });

    testWidgets('Clear empties a value', (tester) async {
      await showForm(
        tester,
        CardioFormState(
          type: CardioType.outdoorRun,
          date: today,
          calories: 310,
        ),
      );

      await tester.tap(find.text('Calories'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '310',
      );
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      verify(() => form.setCalories(null)).called(1);
    });

    testWidgets('leaving with changes asks first; Cancel stays, Discard '
        'leaves', (tester) async {
      await showForm(
        tester,
        CardioFormState(type: CardioType.outdoorRun, date: today),
      );
      when(() => form.hasChanges).thenReturn(true);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this cardio session?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ForgeButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(CardioNewPage), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ForgeButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(find.text('the list'), findsOneWidget);
    });

    testWidgets('leaving without changes does not ask', (tester) async {
      await showForm(
        tester,
        CardioFormState(type: CardioType.outdoorRun, date: today),
      );

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this cardio session?'), findsNothing);
      expect(find.text('the list'), findsOneWidget);
    });
  });
}
