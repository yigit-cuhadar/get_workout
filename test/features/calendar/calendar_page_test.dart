import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/calendar/domain/calendar_days.dart';
import 'package:get_workout/features/calendar/domain/calendar_month.dart';
import 'package:get_workout/features/calendar/presentation/calendar_cubit.dart';
import 'package:get_workout/features/calendar/presentation/calendar_page.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../programs/fixtures.dart';
import '../workout/fixtures.dart';

class _MockCalendar extends MockCubit<CalendarState> implements CalendarCubit {}

class _MockPrograms extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class _MockSettings extends MockCubit<SettingsState> implements SettingsCubit {}

CalendarDate d(int year, int month, int day) => CalendarDate(year, month, day);

void main() {
  setUpAll(() => registerFallbackValue(CalendarFilter.all));

  // Wednesday 11 November 2026.
  final today = d(2026, 11, 11);
  final november = d(2026, 11, 1);
  final pushPull = program(id: 'p1', name: 'Push Pull');
  final active = ActiveProgram(
    programId: 'p1',
    schedule: const {1: 0, 5: 1},
    nextDayIndex: 0,
    nextDate: d(2026, 11, 9),
    startedAt: DateTime(2026, 11, 2),
  );
  final pull = workout(
    'w1',
    [
      exercise('row', [lift(60, 10), lift(60, 10)]),
    ],
    startedAt: DateTime(2026, 11, 10, 18),
    finishedAt: DateTime(2026, 11, 10, 18, 48),
  );
  final older = workout(
    'w2',
    [
      exercise('plank', [const WorkoutSet(durationS: 60, done: true)]),
    ],
    startedAt: DateTime(2026, 11, 3, 18),
    finishedAt: DateTime(2026, 11, 3, 18, 30),
  );
  final ride = CardioSession(
    id: 'c1',
    type: CardioType.outdoorCycle,
    date: DateTime(2026, 11, 11, 7),
    duration: const Duration(minutes: 45),
    distanceKm: 18.4,
  );

  late _MockCalendar calendar;
  late _MockPrograms programs;

  CalendarState ready({
    List<Object> done = const [],
    CalendarFilter filter = CalendarFilter.all,
    bool withProgram = true,
  }) {
    final (:from, :to) = monthRange(november);
    return CalendarState(
      month: november,
      weeks: monthWeeks(november, firstWeekday: DateTime.monday),
      selected: today,
      today: today,
      filter: filter,
      status: CalendarStatus.ready,
      entries: calendarEntries(
        from: from,
        to: to,
        today: today,
        workouts: [...done.whereType<Workout>()],
        cardio: [...done.whereType<CardioSession>()],
        active: withProgram ? active : null,
        program: withProgram ? pushPull : null,
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester,
    CalendarState state, {
    bool premium = true,
    Program? copy,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 3600)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    calendar = _MockCalendar();
    whenListen(
      calendar,
      const Stream<CalendarState>.empty(),
      initialState: state,
    );
    programs = _MockPrograms();
    whenListen(
      programs,
      const Stream<ProgramListState>.empty(),
      initialState: ProgramListState(
        status: ProgramListStatus.ready,
        programs: [copy ?? pushPull],
        active: active,
        premium: premium,
      ),
    );
    when(() => programs.firstWeekday).thenReturn(DateTime.monday);
    sl
      ..registerFactoryParam<CalendarCubit, int, void>((_, _) => calendar)
      ..registerSingleton<ProgramListCubit>(programs);
    final settings = _MockSettings();
    when(() => settings.state).thenReturn(
      const SettingsState(
        UserSettings(
          weightUnit: WeightUnit.kg,
          lengthUnit: LengthUnit.cm,
          weekStart: WeekStart.monday,
        ),
        loaded: true,
      ),
    );
    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: settings,
        child: MaterialApp(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CalendarPage(),
        ),
      ),
    );
    await tester.pump();
  }

  tearDown(sl.reset);

  testWidgets('the month, its counts, the filter and its weeks', (
    tester,
  ) async {
    await pump(tester, ready(done: [pull, older, ride]));
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('2 workouts · 1 cardio · 1 missed'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('This week · Nov 9–15'), findsOneWidget);
    expect(find.text('Earlier this month'), findsOneWidget);
    expect(find.text('Outdoor cycling'), findsOneWidget);
    expect(find.text('Cardio · 18.4 km'), findsOneWidget);
    expect(find.text('Workout w2'), findsOneWidget);
    // No volume: the sets.
    expect(find.text('30 min · 1 set'), findsOneWidget);
    expect(find.widgetWithText(ListRow, 'Missed'), findsOneWidget);
    expect(find.text('Do it today'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('a chip filters', (tester) async {
    await pump(tester, ready(done: [pull, ride]));
    await tester.tap(find.widgetWithText(ForgeChip, 'Cardio'));
    verify(() => calendar.filter(CalendarFilter.cardio)).called(1);
  });

  testWidgets('a chip with nothing says so with its action', (tester) async {
    await pump(tester, ready(done: [pull], filter: CalendarFilter.cardio));
    expect(find.text('No cardio in November'), findsOneWidget);
    expect(find.text('Log cardio'), findsOneWidget);
  });

  testWidgets('nothing logged: the planned days, then the message', (
    tester,
  ) async {
    await pump(tester, ready());
    expect(find.text('Nothing logged in November'), findsOneWidget);
    expect(find.text('Add past workout'), findsOneWidget);
    expect(find.text('All'), findsNothing);
    expect(find.text('This week · Nov 9–15'), findsOneWidget);
  });

  testWidgets('a locked copy: Start locked, the missed day without Do it '
      'today', (tester) async {
    final locked = program(id: 'p1', name: 'Push Pull', premium: true);
    final (:from, :to) = monthRange(november);
    final state = CalendarState(
      month: november,
      weeks: monthWeeks(november, firstWeekday: DateTime.monday),
      selected: today,
      today: today,
      status: CalendarStatus.ready,
      entries: calendarEntries(
        from: from,
        to: to,
        today: today,
        workouts: [pull],
        cardio: const [],
        active: active,
        program: locked,
      ),
    );
    await pump(tester, state, premium: false, copy: locked);
    expect(find.text('Do it today'), findsNothing);
    expect(
      tester
          .widget<ForgeButton>(find.widgetWithText(ForgeButton, 'Start'))
          .locked,
      isTrue,
    );
  });

  testWidgets('holding the next day opens Move, off until a day is picked', (
    tester,
  ) async {
    await pump(tester, ready(done: [pull]));
    await tester.longPress(find.widgetWithText(ListRow, 'Missed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Move '), findsWidgets);
    expect(find.text('The days after it keep their order.'), findsOneWidget);
    final move = tester.widget<ForgeButton>(
      find.widgetWithText(ForgeButton, 'Move'),
    );
    expect(move.onPressed, isNull);
  });

  testWidgets('a month that failed says so in its card', (tester) async {
    await pump(
      tester,
      CalendarState(
        month: november,
        weeks: monthWeeks(november, firstWeekday: DateTime.monday),
        selected: today,
        today: today,
        status: CalendarStatus.failure,
        failure: const NetworkFailure(),
      ),
    );
    expect(find.text("Couldn't load your calendar"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    verify(calendar.retry).called(1);
  });
}
