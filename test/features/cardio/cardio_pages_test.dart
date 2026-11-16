import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/cardio/domain/cardio_week.dart';
import 'package:get_workout/features/cardio/presentation/cardio_form_cubit.dart';
import 'package:get_workout/features/cardio/presentation/cardio_list_cubit.dart';
import 'package:get_workout/features/cardio/presentation/cardio_list_page.dart';
import 'package:get_workout/features/cardio/presentation/cardio_session_page.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
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
}
