import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/presentation/premium_prompt.dart';
import 'package:get_workout/features/programs/presentation/program_detail_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/programs/presentation/programs_page.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../features/programs/fixtures.dart' show program;
import 'today_stand_ins.dart';

class MockWorkoutCubit extends MockCubit<ActiveWorkoutState>
    implements ActiveWorkoutCubit {}

class MockProgramListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class MockProgramDetailCubit extends MockCubit<ProgramDetailState>
    implements ProgramDetailCubit {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class MockBodyModelCubit extends MockCubit<BodyModelState>
    implements BodyModelCubit {}

void main() {
  late MockWorkoutCubit cubit;

  tearDown(sl.reset);

  /// The Programs tab, with no programs unless given; the workout is a stub
  /// saying where it is, so this tests the tab's links, not the workout page.
  Future<void> start(
    WidgetTester tester, {
    ActiveWorkoutState state = const ActiveWorkoutState(
      status: WorkoutStatus.none,
    ),
    ProgramListState? programs,
  }) async {
    if (programs != null) {
      final list = MockProgramListCubit();
      when(() => list.state).thenReturn(programs);
      sl.registerSingleton<ProgramListCubit>(list);
    }
    final detail = MockProgramDetailCubit();
    when(() => detail.state).thenReturn(const ProgramDetailState());
    sl
      ..registerSingleton(PremiumPrompt((_) async => false))
      ..registerFactoryParam<ProgramDetailCubit, String, void>(
        (_, _) => detail,
      );
    final catalogue = MockCatalogueCubit();
    // Failed, not loading: a loading card shimmers, which never settles.
    when(() => catalogue.state)
        .thenReturn(const CatalogueFailed(UnknownFailure('offline')));
    final model = MockBodyModelCubit();
    when(() => model.state).thenReturn(const BodyModelLoading());
    when(model.load).thenAnswer((_) async {});
    cubit = MockWorkoutCubit();
    when(() => cubit.state).thenReturn(state);
    when(() => cubit.startFree(any())).thenReturn(true);
    registerTodayStandIns();
    final router = GoRouter(
      initialLocation: Routes.programs,
      routes: [
        GoRoute(path: Routes.programs, builder: (_, _) => const ProgramsPage()),
        GoRoute(
          path: Routes.workout,
          builder: (_, _) => const Scaffold(body: Text('at workout')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ActiveWorkoutCubit>.value(value: cubit),
          askedRestAlerts(),
          BlocProvider<ExerciseCatalogueCubit>.value(value: catalogue),
          BlocProvider<BodyModelCubit>.value(value: model),
          unknownPremium(),
          programList(),
          defaultSettings(),
        ],
        child: MaterialApp.router(
          theme: ThemeData(
            extensions: AppPreset.shipped.lightTheme().extensions.values,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty workout starts on Today, not here', (tester) async {
    await start(tester);

    expect(find.text('Ready-made programs'), findsOneWidget);
    expect(find.text('Start empty workout'), findsNothing);
  });

  testWidgets('the active program comes first, then the three ways in', (
    tester,
  ) async {
    await start(
      tester,
      programs: ProgramListState(
        status: ProgramListStatus.ready,
        programs: [program(id: 'p1')],
        active: ActiveProgram(
          programId: 'p1',
          schedule: const {1: 0, 4: 1},
          nextDayIndex: 1,
          nextDate: CalendarDate(2026, 11, 12),
          startedAt: DateTime(2026, 11, 2),
        ),
        nextDate: CalendarDate(2026, 11, 12),
        premium: false,
      ),
    );

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    final order = [
      'Upper Lower',
      'Ready-made programs',
      'Generate a program',
      'New program',
    ].map(top).toList();
    expect(order, [...order]..sort());
    // Today starts the day.
    expect(find.text('Start Lower'), findsNothing);
  });

  testWidgets('without an active program the prompt, then the ways in', (
    tester,
  ) async {
    await start(tester);

    expect(
      tester.getTopLeft(find.text('No active program')).dy,
      lessThan(tester.getTopLeft(find.text('Ready-made programs')).dy),
    );
    expect(find.text('Active program'), findsNothing);
  });
}
