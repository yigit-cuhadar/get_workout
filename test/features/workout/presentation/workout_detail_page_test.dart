import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/presentation/workout_detail_cubit.dart';
import 'package:get_workout/features/workout/presentation/workout_detail_page.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../../programs/fixtures.dart' as programs;
import '../fixtures.dart';

class _MockDetail extends MockCubit<WorkoutDetailState>
    implements WorkoutDetailCubit {}

class _MockPrograms extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class _MockSettings extends MockCubit<SettingsState> implements SettingsCubit {}

class _MockCatalogue extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

void main() {
  late _MockDetail detail;

  final push = workout(
    'w1',
    [
      exercise('Bench Press', [lift(40, 10), lift(82.5, 8)]),
      exercise('Incline Press', [lift(30, 10)]),
    ],
    startedAt: DateTime(2026, 11, 13, 18, 5),
    finishedAt: DateTime(2026, 11, 13, 18, 57),
    programId: 'p1',
    dayIndex: 0,
  );

  Future<void> pump(
    WidgetTester tester,
    WorkoutDetailState state, {
    ProgramListState programs = const ProgramListState(),
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 2600)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    detail = _MockDetail();
    whenListen(
      detail,
      const Stream<WorkoutDetailState>.empty(),
      initialState: state,
    );
    when(detail.delete).thenAnswer((_) async {});
    final programList = _MockPrograms();
    whenListen(
      programList,
      const Stream<ProgramListState>.empty(),
      initialState: programs,
    );
    sl
      ..registerFactoryParam<WorkoutDetailCubit, String, void>((_, _) => detail)
      ..registerSingleton<ProgramListCubit>(programList);
    final settings = _MockSettings();
    when(() => settings.state).thenReturn(
      const SettingsState(
        UserSettings(weightUnit: WeightUnit.kg, lengthUnit: LengthUnit.cm),
        loaded: true,
      ),
    );
    final catalogue = _MockCatalogue();
    when(() => catalogue.state).thenReturn(const CatalogueReady([]));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<ExerciseCatalogueCubit>.value(value: catalogue),
        ],
        child: MaterialApp(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WorkoutDetailPage(
            id: 'w1',
            routes: Routes.calendarEditing,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  tearDown(sl.reset);

  WorkoutDetailState ready({bool pending = false, Set<(int, int)>? records}) =>
      WorkoutDetailState(
        status: WorkoutDetailStatus.ready,
        workout: push,
        pending: pending,
        records: records,
      );

  testWidgets('the band holds the start, the name and four figures', (
    tester,
  ) async {
    await pump(tester, ready(records: {(0, 1)}));
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Fri, Nov 13 · 6:05 PM'), findsOneWidget);
    expect(find.text('Workout w1'), findsOneWidget);
    expect(find.text('52 min'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('record'), findsOneWidget);
  });

  testWidgets('records read as a dash until known', (tester) async {
    await pump(tester, ready());
    expect(find.text('—'), findsWidgets);
    expect(find.text('record'), findsNothing);
  });

  testWidgets('the active copy\'s program names the week of its run', (
    tester,
  ) async {
    await pump(
      tester,
      ready(),
      programs: ProgramListState(
        status: ProgramListStatus.ready,
        programs: [programs.program(id: 'p1', name: 'Push Pull Legs')],
        active: ActiveProgram(
          programId: 'p1',
          weekdays: const [1, 3, 5],
          nextDayIndex: 1,
          nextDate: CalendarDate(2026, 11, 16),
          startedAt: DateTime(2026, 10, 27, 9),
        ),
      ),
    );
    expect(find.text('Push Pull Legs · week 3'), findsOneWidget);
  });

  testWidgets('a deleted program says so', (tester) async {
    await pump(
      tester,
      ready(),
      programs: const ProgramListState(status: ProgramListStatus.ready),
    );
    expect(find.text('From a program you deleted'), findsOneWidget);
  });

  testWidgets('the first exercise is open; a header opens another', (
    tester,
  ) async {
    await pump(tester, ready());
    expect(find.text('82.5 kg × 8'), findsOneWidget);
    expect(find.text('30 kg × 10'), findsNothing);
    await tester.tap(find.text('Incline Press'));
    await tester.pump();
    expect(find.text('30 kg × 10'), findsOneWidget);
  });

  testWidgets('⋯ deletes after asking', (tester) async {
    await pump(tester, ready());
    await tester.tap(find.bySemanticsLabel('Workout options'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Delete workout'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this workout?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ForgeButton, 'Delete'));
    await tester.pumpAndSettle();
    verify(detail.delete).called(1);
  });

  testWidgets('waiting to sync: a notice and no options', (tester) async {
    await pump(tester, ready(pending: true));
    expect(find.text('Waiting to sync'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Workout options'));
    await tester.pumpAndSettle();
    expect(find.text('Delete workout'), findsNothing);
  });

  testWidgets('a workout gone shows one line', (tester) async {
    await pump(
      tester,
      const WorkoutDetailState(status: WorkoutDetailStatus.missing),
    );
    expect(find.text('This workout no longer exists'), findsOneWidget);
  });

  testWidgets('a load failure offers a retry', (tester) async {
    await pump(
      tester,
      const WorkoutDetailState(
        status: WorkoutDetailStatus.failure,
        failure: NetworkFailure(),
      ),
    );
    expect(find.text("Couldn't load your workouts"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
