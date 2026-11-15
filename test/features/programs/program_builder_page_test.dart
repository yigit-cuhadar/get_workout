import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/unsaved_changes.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_validation.dart';
import 'package:get_workout/features/programs/presentation/program_builder_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_builder_page.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class _BuilderCubit extends MockCubit<ProgramBuilderState>
    implements ProgramBuilderCubit {}

class _CatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

void main() {
  final exercises = [
    for (final id in ['a', 'b', 'c', 'd']) move(id, name: 'Move $id'),
  ];
  final byId = {for (final e in exercises) e.id: e};

  late _BuilderCubit cubit;

  setUp(() {
    cubit = _BuilderCubit();
    when(() => cubit.isEditing).thenReturn(true);
    when(() => cubit.hasChanges).thenReturn(false);
    when(() => cubit.weightUnit).thenReturn(WeightUnit.kg);
    when(() => cubit.load()).thenAnswer((_) async {});
    sl.registerFactoryParam<ProgramBuilderCubit, String?, WeightUnit>(
      (_, _) => cubit,
    );
  });

  tearDown(sl.reset);

  ProgramBuilderState editing(
    Program program, {
    int selectedDay = 0,
    ProgramValidation validation = const ProgramValidation(),
  }) => ProgramBuilderState(
    status: ProgramBuilderStatus.editing,
    program: program,
    selectedDay: selectedDay,
    exercises: byId,
    catalogueReady: true,
    customExercisesReady: true,
    validation: validation,
  );

  Future<void> pump(WidgetTester tester, ProgramBuilderState state) async {
    tester.view
      ..physicalSize = const Size(1200, 3600)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    when(() => cubit.state).thenReturn(state);
    final catalogue = _CatalogueCubit();
    when(() => catalogue.state).thenReturn(CatalogueReady(exercises));
    final settings = _SettingsCubit();
    when(() => settings.state)
        .thenReturn(SettingsState(UserSettings.defaultsFor(null)));
    final router = GoRouter(
      initialLocation: '/edit',
      routes: [
        GoRoute(
          path: '/edit',
          builder: (_, _) => RepositoryProvider.value(
            value: UnsavedChanges(),
            child: const ProgramBuilderPage(programId: 'p1'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ExerciseCatalogueCubit>.value(value: catalogue),
          BlocProvider<SettingsCubit>.value(value: settings),
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
  }

  Finder dayOptions() => find.bySemanticsLabel('Day options');

  testWidgets('the program: name, length, day chips, summary and rows', (
    tester,
  ) async {
    await pump(tester, editing(program(name: 'Upper Lower')));

    expect(find.text('Edit program'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Program name'), findsWidgets);
    expect(find.text('Length in weeks (optional)'), findsOneWidget);
    expect(find.text('Leave empty to run until you stop it'), findsOneWidget);
    expect(find.text('Upper'), findsOneWidget);
    expect(find.text('Lower'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(find.textContaining('Upper · 2 exercises · ~'), findsOneWidget);
    expect(find.text('Move a'), findsOneWidget);
    expect(find.text('Add exercises'), findsOneWidget);
    expect(find.text('A day holds up to 20 exercises.'), findsNothing);
  });

  testWidgets('the selected day\'s ⋯ opens its menu', (tester) async {
    await pump(tester, editing(program()));

    expect(dayOptions(), findsOneWidget, reason: 'on the selected chip only');
    await tester.tap(dayOptions());
    await tester.pumpAndSettle();
    expect(find.text('Rename day'), findsOneWidget);
    expect(find.text('Duplicate day'), findsOneWidget);
    expect(find.text('Move earlier'), findsNothing);
    expect(find.text('Move later'), findsOneWidget);
    expect(find.text('Delete day'), findsOneWidget);

    await tester.tap(find.text('Duplicate day'));
    await tester.pumpAndSettle();
    verify(() => cubit.duplicateDay(0, any())).called(1);
  });

  testWidgets('deleting a day with exercises asks first', (tester) async {
    await pump(tester, editing(program()));

    await tester.tap(dayOptions());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete day'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this day and its exercises?'), findsOneWidget);
    expect(find.text('Its 2 exercises are removed too.'), findsOneWidget);

    await tester.tap(find.widgetWithText(ForgeButton, 'Delete day'));
    await tester.pumpAndSettle();
    verify(() => cubit.deleteDay(0)).called(1);
  });

  testWidgets('+ Day adds a day, then asks its name', (tester) async {
    final start = program();
    await pump(tester, editing(start));
    final added = start.copyWith(days: [...start.days, const ProgramDay()]);
    when(() => cubit.addDay()).thenAnswer(
      (_) => when(() => cubit.state).thenReturn(editing(added, selectedDay: 2)),
    );

    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(find.text('Rename day'), findsOneWidget);
    expect(
      find.text("Shown on the day's chip and in your workouts."),
      findsOneWidget,
    );
    expect(find.text('Day 3'), findsWidgets);
    expect(
      tester.widget<ForgeTextField>(find.byType(ForgeTextField).last).autofocus,
      isTrue,
    );

    await tester.enterText(find.byType(TextField).last, 'Arms');
    await tester.tap(find.widgetWithText(ForgeButton, 'Save'));
    await tester.pumpAndSettle();
    verify(() => cubit.renameDay(2, 'Arms')).called(1);
  });

  testWidgets('an empty day says so; after a save it is an error', (
    tester,
  ) async {
    const empty = Program(name: 'Push', days: [ProgramDay()]);
    await pump(tester, editing(empty));
    expect(find.text('No exercises on this day'), findsOneWidget);
    expect(
      find.text('Add exercises; they keep the order you set.'),
      findsOneWidget,
    );

    await pump(
      tester,
      editing(
        empty,
        validation: const ProgramValidation(
          program: {ProgramIssue.nameMissing},
          days: {
            0: {DayIssue.noItems},
          },
        ),
      ),
    );
    expect(find.text('No exercises on this day'), findsNothing);
    expect(find.text('Add at least one exercise to this day'), findsOneWidget);
    expect(find.text('Enter a name'), findsOneWidget);
  });

  testWidgets('an unavailable exercise is replaced or removed from its ⋯', (
    tester,
  ) async {
    await pump(
      tester,
      editing(
        Program(
          name: 'Push',
          days: [
            ProgramDay(items: [item('a'), item('gone')]),
          ],
        ),
      ),
    );

    expect(find.text('Unavailable exercise'), findsOneWidget);
    expect(
      find.text('No longer in the library. Replace or remove it.'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Exercise options').last);
    await tester.pumpAndSettle();
    expect(find.text('Replace exercise'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    verify(() => cubit.removeItem(1)).called(1);
  });

  testWidgets('a full day says how many it holds', (tester) async {
    await pump(
      tester,
      editing(
        Program(
          name: 'Push',
          days: [
            ProgramDay(items: [for (var i = 0; i < 20; i++) item('a')]),
          ],
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('A day holds up to 20 exercises.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('A day holds up to 20 exercises.'), findsOneWidget);
    expect(
      tester.widget<ForgeAddButton>(find.byType(ForgeAddButton)).onPressed,
      isNull,
    );
  });

  testWidgets('the sets and reps sheet; Rest opens the wheel', (tester) async {
    await pump(tester, editing(program()));

    await tester.tap(find.text('Sets').first);
    await tester.pumpAndSettle();
    expect(find.text('Move a'), findsNWidgets(2), reason: 'the sheet title');
    expect(find.text('Reps from'), findsOneWidget);
    expect(find.text('Target weight (kg, optional)'), findsOneWidget);
    expect(find.text('1:30'), findsWidgets);

    await tester.tap(find.widgetWithText(ForgeTextField, 'Rest'));
    await tester.pumpAndSettle();
    expect(find.byType(ForgeDurationWheel), findsOneWidget);
  });

  testWidgets('not found and load failure use the standard forms', (
    tester,
  ) async {
    await pump(
      tester,
      ProgramBuilderState(
        status: ProgramBuilderStatus.notFound,
        program: program(),
      ),
    );
    expect(find.text('This program no longer exists.'), findsOneWidget);
    expect(find.text('Save'), findsNothing);

    await pump(
      tester,
      ProgramBuilderState(
        status: ProgramBuilderStatus.loadFailed,
        program: program(),
      ),
    );
    expect(find.text("Couldn't load your programs."), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    verify(() => cubit.load()).called(1);
  });
}
