import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/admin/access/domain/access_usecases.dart';
import 'package:get_workout/admin/access/domain/admin_access_repository.dart';
import 'package:get_workout/admin/exercises/domain/admin_exercise_repository.dart';
import 'package:get_workout/admin/exercises/domain/exercise_admin_usecases.dart';
import 'package:get_workout/admin/exercises/domain/exercise_draft.dart';
import 'package:get_workout/admin/exercises/presentation/exercise_editor_cubit.dart';
import 'package:get_workout/admin/exercises/presentation/exercise_editor_page.dart';
import 'package:get_workout/admin/exercises/presentation/exercise_list_cubit.dart';
import 'package:get_workout/admin/exercises/presentation/exercise_list_page.dart';
import 'package:get_workout/admin/programs/domain/admin_program_repository.dart';
import 'package:get_workout/admin/programs/domain/program_admin_usecases.dart';
import 'package:get_workout/features/exercises/domain/content_rules.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockRepository extends Mock implements AdminExerciseRepository {}

class MockAccessRepository extends Mock implements AdminAccessRepository {}

class MockProgramRepository extends Mock implements AdminProgramRepository {}

void main() {
  late MockRepository repository;
  late StreamController<List<ExerciseRecord>> library;

  final press = record(validJson());
  final curl = record(
    validJson(id: 'ex_curl', name: 'Curl', popularity: 2, family: 'curl'),
  );

  setUpAll(() => registerFallbackValue(const ExerciseDraft()));

  setUp(() {
    repository = MockRepository();
    library = StreamController.broadcast();
    when(() => repository.watchAll()).thenAnswer((_) => library.stream);
    when(() => repository.load('ex_dumbbell_press'))
        .thenAnswer((_) async => Ok(press));
  });

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    // A 1280px window less the left menu.
    tester.view
      ..physicalSize = const Size(1048, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: ForgeTheme.light(), home: page));
  }

  test('every field the editor has an input for is a known field', () {
    final known = {
      ...allowedKeys.difference({'l10n'}),
      for (final key in allowedTextKeys) 'l10n.en.$key',
    };
    // Status is set by the save bar, not a field.
    expect(exerciseEditorFields.keys.toSet(), known.difference({'status'}));
  });

  testWidgets('the list filters by status from the filter column', (
    tester,
  ) async {
    final programs = MockProgramRepository();
    when(programs.watchAll).thenAnswer((_) => Stream.value([]));
    final cubit = ExerciseListCubit(
      watchExerciseRecords: WatchExerciseRecords(repository),
      watchPrograms: WatchPrograms(programs),
    );
    addTearDown(cubit.close);
    await pumpPage(
      tester,
      BlocProvider.value(value: cubit, child: const ExerciseListPage()),
    );
    library.add([press, curl]);
    await tester.pumpAndSettle();

    expect(find.text('Showing 2 of 2'), findsOneWidget);
    expect(find.textContaining('Library health'), findsOneWidget);

    await tester.tap(find.text('Draft · 0'));
    await tester.pump();

    expect(find.text('Showing 0 of 2'), findsOneWidget);
    expect(find.text('No results'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.text('Showing 2 of 2'), findsOneWidget);

    // No program uses either exercise; the library health flags neither.
    expect(find.text('Problems only · 0'), findsOneWidget);
    expect(find.text('Unused by programs · 2'), findsOneWidget);
    final unused = find.byType(ForgeSwitch).last;
    await tester.ensureVisible(unused);
    await tester.pumpAndSettle();
    await tester.tap(unused);
    await tester.pump();
    expect(cubit.state.unusedOnly, isTrue);
    expect(find.text('Showing 2 of 2'), findsOneWidget);

    await tester.tap(find.text('Name'));
    await tester.pump();
    await tester.tap(find.text('Name'));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    final curlTop = tester.getTopLeft(find.text('Curl')).dy;
    expect(
      curlTop,
      greaterThan(tester.getTopLeft(find.text('Dumbbell Press')).dy),
    );
  });

  void registerEditor() =>
      sl.registerFactoryParam<ExerciseEditorCubit, String?, void>(
        (id, _) => ExerciseEditorCubit(
          id: id,
          loadExerciseRecord: LoadExerciseRecord(repository),
          watchExerciseRecords: WatchExerciseRecords(repository),
          createExercise: CreateExercise(repository),
          updateExercise: UpdateExercise(repository),
          checkAdminAccess: CheckAdminAccess(MockAccessRepository()),
        ),
      );

  testWidgets('the Generator tab edits the tier and the stress areas', (
    tester,
  ) async {
    registerEditor();
    addTearDown(sl.reset);
    await pumpPage(tester, const ExerciseEditorPage(id: 'ex_dumbbell_press'));
    library.add([press, curl]);
    await tester.pumpAndSettle();

    // The test font's wide glyphs push the last tab out of the bar.
    await tester.ensureVisible(find.text('Generator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generator'));
    await tester.pumpAndSettle();

    for (final meaning in [
      'A first choice for its slot.',
      'A good alternative.',
      'Only when nothing better fits the equipment.',
      'The generator does not use it.',
    ]) {
      expect(find.text(meaning), findsOneWidget);
    }
    expect(find.byType(RadioMark), findsNWidgets(4));
    // The press has no tier yet.
    expect(find.text('Not rated: counts as standard.'), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(5));

    final cubit = BlocProvider.of<ExerciseEditorCubit>(
      tester.element(find.text('Stress areas')),
    );
    await tester.tap(find.text('Fallback'));
    await tester.pump();
    expect(cubit.state.draft.generatorTier, GeneratorTier.fallback);
    expect(find.text('Not rated: counts as standard.'), findsNothing);
    // Tapping the picked tier clears it again.
    await tester.tap(find.text('Fallback'));
    await tester.pump();
    expect(cubit.state.draft.generatorTier, isNull);
    expect(find.text('Not rated: counts as standard.'), findsOneWidget);
    await tester.tap(find.text('Fallback'));
    await tester.pump();

    await tester.tap(find.text('Knees'));
    await tester.pump();
    await tester.tap(find.text('Elbows and wrists'));
    await tester.pump();
    expect(cubit.state.draft.stressAreas, [
      SensitiveArea.elbowsWrists,
      SensitiveArea.knees,
    ]);
    expect(cubit.state.isDirty, isTrue);
  });

  testWidgets('a problem line opens its tab and focuses its field', (
    tester,
  ) async {
    registerEditor();
    addTearDown(sl.reset);
    await pumpPage(tester, const ExerciseEditorPage(id: 'ex_dumbbell_press'));
    library.add([press, curl]);
    await tester.pumpAndSettle();

    expect(find.text('Dumbbell Press'), findsWidgets);
    expect(find.text('Save (stays Live)'), findsOneWidget);

    final family = find.widgetWithText(TextFormField, 'Family (snake_case)');
    await tester.enterText(family, 'Bad Family');
    await tester.tap(find.text('Muscles'));
    await tester.pumpAndSettle();
    expect(family, findsNothing);

    await tester.tap(find.text('Save (stays Live)'));
    await tester.pumpAndSettle();

    expect(find.text('1 problem blocks saving'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp('Identity, has problems')),
      findsOneWidget,
    );
    semantics.dispose();
    verifyNever(
      () => repository.update(
        any(),
        loadedUpdatedAt: any(named: 'loadedUpdatedAt'),
      ),
    );

    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();

    final field = tester.widget<EditableText>(
      find.descendant(of: family, matching: find.byType(EditableText)),
    );
    expect(field.focusNode.hasFocus, isTrue);
    // The message also stays under the field.
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.textContaining('family'),
      ),
      findsWidgets,
    );
  });
}
