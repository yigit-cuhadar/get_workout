import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/app/train_page.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../features/programs/fixtures.dart' show program;
import '../features/workout/fixtures.dart';
import 'today_stand_ins.dart';

class MockWorkoutCubit extends MockCubit<ActiveWorkoutState>
    implements ActiveWorkoutCubit {}

class MockProgramListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

void main() {
  late MockWorkoutCubit cubit;

  tearDown(sl.reset);

  /// Train on My program, with no programs unless given; the workout is a stub saying
  /// where it is, so this tests Train's links, not the workout page.
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
    cubit = MockWorkoutCubit();
    when(() => cubit.state).thenReturn(state);
    when(() => cubit.startFree(any())).thenReturn(true);
    registerTodayStandIns();
    final router = GoRouter(
      initialLocation: Routes.programs,
      routes: [
        GoRoute(
          path: Routes.programs,
          builder: (_, _) => const TrainPage(view: TrainView.program),
        ),
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
          unknownPremium(),
          programList(),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('My program starts an empty workout and opens it', (
    tester,
  ) async {
    await start(tester);

    await tap(tester, find.text('Start empty workout'));

    verify(() => cubit.startFree('Workout')).called(1);
    expect(find.text('at workout'), findsOneWidget);
  });

  testWidgets('with a workout in progress it asks first', (tester) async {
    await start(
      tester,
      state: ActiveWorkoutState(
        status: WorkoutStatus.active,
        workout: workout('w1', [
          exercise('squat', [lift(100, 5)]),
        ]),
      ),
    );

    await tap(tester, find.text('Start empty workout'));
    expect(find.text('A workout is in progress'), findsOneWidget);
    await tap(tester, find.text('Resume'));

    verifyNever(() => cubit.startFree(any()));
    expect(find.text('at workout'), findsOneWidget);
  });

  testWidgets('the active program comes first, then the four rows', (
    tester,
  ) async {
    await start(
      tester,
      programs: ProgramListState(
        status: ProgramListStatus.ready,
        programs: [program(id: 'p1')],
        active: ActiveProgram(
          programId: 'p1',
          weekdays: const [1, 4],
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
      'Start Lower',
      'Ready-made programs',
      'New program',
      'Start empty workout',
    ].map(top).toList();
    expect(order, [...order]..sort());
  });

  testWidgets('without an active program the rows come first', (tester) async {
    await start(tester);

    expect(
      tester.getTopLeft(find.text('Ready-made programs')).dy,
      lessThan(tester.getTopLeft(find.text('Start empty workout')).dy),
    );
    expect(find.text('Active program'), findsNothing);
  });
}
