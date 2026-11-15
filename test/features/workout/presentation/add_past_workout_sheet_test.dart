import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/workout/domain/workout_editing.dart';
import 'package:get_workout/features/workout/presentation/add_past_workout_sheet.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

class _MockPrograms extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

void main() {
  const program = Program(
    id: 'p1',
    name: 'Push Pull Legs',
    days: [
      ProgramDay(name: 'Push', items: []),
      ProgramDay(name: 'Pull', items: []),
    ],
  );

  /// Opens the sheet; the returned future completes when it closes.
  Future<Future<PastWorkoutPlan?>> open(
    WidgetTester tester, {
    required bool active,
  }) async {
    final programs = _MockPrograms();
    when(() => programs.state).thenReturn(
      ProgramListState(
        status: ProgramListStatus.ready,
        programs: const [program],
        active: active
            ? ActiveProgram(
                programId: 'p1',
                weekdays: const [1, 3],
                nextDayIndex: 0,
                nextDate: CalendarDate(2026, 11, 16),
                startedAt: DateTime(2026, 11, 1),
              )
            : null,
      ),
    );
    late Future<PastWorkoutPlan?> result;
    await tester.pumpWidget(
      BlocProvider<ProgramListCubit>.value(
        value: programs,
        child: MaterialApp(
          theme: AppPreset.shipped.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = askPastWorkout(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('no active program: no program day row', (tester) async {
    await open(tester, active: false);
    expect(find.text('Add past workout'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Start time'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('Program day'), findsNothing);
  });

  testWidgets('a picked program day fills the plan and its name', (
    tester,
  ) async {
    final result = await open(tester, active: true);
    expect(find.text('Fills the exercises from the day'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    await tester.tap(find.text('Program day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    final plan = await result;
    expect(plan!.name, 'Pull');
    expect(plan.dayIndex, 1);
    expect(plan.program, program);
  });
}
