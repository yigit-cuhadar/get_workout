import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/admin/access/domain/access_usecases.dart';
import 'package:get_workout/admin/access/domain/admin_access_repository.dart';
import 'package:get_workout/admin/exercises/domain/admin_exercise_repository.dart';
import 'package:get_workout/admin/exercises/domain/exercise_admin_usecases.dart';
import 'package:get_workout/admin/exercises/domain/exercise_draft.dart';
import 'package:get_workout/admin/programs/domain/admin_program_repository.dart';
import 'package:get_workout/admin/programs/domain/program_admin_usecases.dart';
import 'package:get_workout/admin/programs/domain/program_draft.dart';
import 'package:get_workout/admin/programs/presentation/program_editor_cubit.dart';
import 'package:get_workout/admin/programs/presentation/program_editor_page.dart';
import 'package:get_workout/admin/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/admin/programs/presentation/program_list_page.dart';
import 'package:get_workout/features/programs/domain/catalogue_rules.dart';
import 'package:mocktail/mocktail.dart';

import 'program_fixtures.dart';

class MockProgramRepository extends Mock implements AdminProgramRepository {}

class MockExerciseRepository extends Mock implements AdminExerciseRepository {}

class MockAccessRepository extends Mock implements AdminAccessRepository {}

void main() {
  late MockProgramRepository repository;
  late MockExerciseRepository exerciseRepository;
  late StreamController<List<ProgramRecord>> cards;
  late StreamController<List<ExerciseRecord>> library;

  const id = 'pr_dumbbell_basics';
  final basics = programRecord(programJson());
  final strength = programRecord(
    cardOf(
      programJson(id: 'pr_strength', name: 'Strength', order: 2, premium: true),
    ),
  );

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue((card: null, detail: null) as ProgramVersion);
  });

  setUp(() {
    repository = MockProgramRepository();
    exerciseRepository = MockExerciseRepository();
    cards = StreamController.broadcast();
    library = StreamController.broadcast();
    when(() => repository.watchCards()).thenAnswer((_) => cards.stream);
    when(() => repository.load(id)).thenAnswer((_) async => Ok(basics));
    when(() => exerciseRepository.watchAll()).thenAnswer((_) => library.stream);
  });

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    // A 1280px window less the left menu.
    tester.view
      ..physicalSize = const Size(1048, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: ForgeTheme.light(), home: page));
  }

  test('every field outside the days the editor has an input for is known', () {
    final known = {
      ...programKeys,
      for (final key in programTextKeys) 'l10n.en.$key',
    };
    expect(known, containsAll(programEditorFields.keys));
  });

  testWidgets('the list shows the live split and filters by status', (
    tester,
  ) async {
    final cubit = ProgramListCubit(
      watchProgramCards: WatchProgramCards(repository),
    );
    addTearDown(cubit.close);
    await pumpPage(
      tester,
      BlocProvider.value(value: cubit, child: const ProgramListPage()),
    );
    cards.add([basics, strength]);
    await tester.pumpAndSettle();

    expect(find.text('Showing 2 of 2'), findsOneWidget);
    expect(
      find.text('Catalogue health: 1 problem(s) · live: 1 free, 1 premium'),
      findsOneWidget,
    );
    expect(find.text('Premium'), findsOneWidget);

    await tester.tap(find.text('Draft · 0'));
    await tester.pump();

    expect(find.text('Showing 0 of 2'), findsOneWidget);
    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('the editor sums up the days on the right, and a problem line '
      'focuses its exercise field', (tester) async {
    sl.registerFactoryParam<ProgramEditorCubit, String?, void>(
      (id, _) => ProgramEditorCubit(
        id: id,
        loadProgramRecord: LoadProgramRecord(repository),
        watchProgramCards: WatchProgramCards(repository),
        watchExerciseRecords: WatchExerciseRecords(exerciseRepository),
        createProgram: CreateProgram(repository),
        updateProgram: UpdateProgram(repository),
        checkAdminAccess: CheckAdminAccess(MockAccessRepository()),
      ),
    );
    addTearDown(sl.reset);
    await pumpPage(tester, const ProgramEditorPage(id: id));
    cards.add([basics, strength]);
    library.add(exerciseRecords);
    await tester.pumpAndSettle();

    expect(find.text('Dumbbell Basics'), findsWidgets);
    expect(find.text('Days per week'), findsOneWidget);
    expect(find.textContaining('Superset A'), findsNWidgets(2));
    expect(find.text('Save (stays Live)'), findsOneWidget);

    // Day B's first exercise loses its sets.
    final sets = find.widgetWithText(TextFormField, '3').at(2);
    final focus = tester
        .widget<EditableText>(
          find.descendant(of: sets, matching: find.byType(EditableText)),
        )
        .focusNode;
    await tester.enterText(sets, '');
    await tester.pump();
    await tester.tap(find.text('Save (stays Live)'));
    await tester.pumpAndSettle();

    expect(find.text('1 problem blocks saving'), findsOneWidget);
    verifyNever(() => repository.update(any(), loaded: any(named: 'loaded')));

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);

    await tester.tap(find.text('Day 2, exercise 1'));
    await tester.pumpAndSettle();

    expect(focus.hasFocus, isTrue);
    // The message also stays under the row.
    expect(find.textContaining('days[1].items[0] sets'), findsWidgets);
  });
}
