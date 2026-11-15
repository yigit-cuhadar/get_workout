import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_detail_cubit.dart';
import 'package:get_workout/features/exercises/presentation/library_cubit.dart';
import 'package:get_workout/features/programs/presentation/exercise_picker_cubit.dart';
import 'package:get_workout/features/programs/presentation/exercise_picker_page.dart';
import 'package:get_workout/features/programs/programs_module.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../exercises/fixtures.dart';

class _CatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class _LibraryCubit extends MockCubit<LibraryState> implements LibraryCubit {}

class _DetailCubit extends MockCubit<ExerciseDetailState>
    implements ExerciseDetailCubit {}

void main() {
  final bench = exercise('bench', name: 'Bench Press');
  final dumbbell = exercise('dumbbell', name: 'Dumbbell Bench Press');
  final incline = exercise('incline', name: 'Incline Bench Press');
  final fly = exercise('fly', name: 'Cable Fly');
  final all = [bench, dumbbell, incline, fly];

  late _LibraryCubit library;
  late _DetailCubit detail;
  late List<Exercise>? picked;

  setUp(() {
    picked = null;
    library = _LibraryCubit();
    when(() => library.state).thenReturn(LibraryState(results: all));
    when(() => library.setLanguage(any())).thenReturn(null);
    detail = _DetailCubit();
    when(() => detail.state).thenReturn(
      DetailReady(bench, alternatives: [dumbbell], variations: [incline]),
    );
    sl
      ..registerFactory<LibraryCubit>(
        () => library,
        instanceName: ProgramsModule.pickerLibrary,
      )
      ..registerFactoryParam<ExercisePickerCubit, int, bool>(
        (max, multiple) => ExercisePickerCubit(max: max, multiple: multiple),
      )
      ..registerFactoryParam<ExerciseDetailCubit, String, void>(
        (_, _) => detail,
      );
  });

  tearDown(sl.reset);

  Future<void> pump(WidgetTester tester, ExercisePickerPage page) async {
    tester.view
      ..physicalSize = const Size(1500, 3600)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final catalogue = _CatalogueCubit();
    when(() => catalogue.state).thenReturn(CatalogueReady(all));
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => TextButton(
            onPressed: () async =>
                picked = await context.push<List<Exercise>>('/pick'),
            child: const Text('open'),
          ),
          routes: [GoRoute(path: 'pick', builder: (_, _) => page)],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      BlocProvider<ExerciseCatalogueCubit>.value(
        value: catalogue,
        child: MaterialApp.router(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('adding: the bar counts the chosen ones and adds them', (
    tester,
  ) async {
    await pump(
      tester,
      const ExercisePickerPage(max: 3, limit: 40, multiple: true),
    );

    expect(find.text('Add exercises'), findsNWidgets(2));
    expect(find.text('None chosen'), findsOneWidget);
    expect(find.text('4 exercises'), findsOneWidget);

    await tester.tap(find.text('Bench Press'));
    await tester.tap(find.text('Cable Fly'));
    await tester.pump();
    expect(find.text('2 chosen'), findsOneWidget);

    await tester.tap(find.text('Add 2 exercises'));
    await tester.pumpAndSettle();
    expect(ids(picked!), ['bench', 'fly']);
  });

  testWidgets('at the limit the other rows take no taps', (tester) async {
    await pump(
      tester,
      const ExercisePickerPage(max: 2, limit: 40, multiple: true),
    );

    await tester.tap(find.text('Bench Press'));
    await tester.tap(find.text('Cable Fly'));
    await tester.pump();
    expect(find.text('2 chosen · 40 is the most'), findsOneWidget);

    await tester.tap(find.text('Incline Bench Press'));
    await tester.pump();
    expect(find.text('2 chosen · 40 is the most'), findsOneWidget);

    // A chosen one can still be let go.
    await tester.tap(find.text('Bench Press'));
    await tester.pump();
    expect(find.text('1 chosen'), findsOneWidget);
  });

  testWidgets('the generator leaves exercises out', (tester) async {
    await pump(
      tester,
      const ExercisePickerPage(
        max: 20,
        limit: 20,
        multiple: true,
        form: ExercisePickerForm.leaveOut,
      ),
    );

    expect(find.text('Leave out exercises'), findsNWidgets(2));
    await tester.tap(find.text('Cable Fly'));
    await tester.pump();
    expect(find.text('Leave out 1 exercise'), findsOneWidget);
  });

  testWidgets('swapping lists the similar ones first and swaps on a tap', (
    tester,
  ) async {
    await pump(
      tester,
      const ExercisePickerPage(
        max: 1,
        limit: 40,
        multiple: false,
        form: ExercisePickerForm.swap,
        exerciseId: 'bench',
        logged: 2,
      ),
    );

    expect(find.text('Swap Bench Press'), findsOneWidget);
    expect(
      find.text('Sets 1 and 2 are logged; the rest move to the new exercise.'),
      findsOneWidget,
    );
    expect(find.text('None chosen'), findsNothing);
    final similar = tester.getTopLeft(find.text('Similar')).dy;
    final rest = tester.getTopLeft(find.text('All exercises')).dy;
    final first = tester.getTopLeft(find.text('Dumbbell Bench Press')).dy;
    expect(first, allOf(greaterThan(similar), lessThan(rest)));
    expect(tester.getTopLeft(find.text('Cable Fly')).dy, greaterThan(rest));
    // The exercise being swapped is not offered for itself.
    expect(find.text('Bench Press'), findsNothing);
    expect(find.text('Alternative'), findsOneWidget);
    expect(find.text('Variation'), findsOneWidget);

    await tester.tap(find.text('Incline Bench Press'));
    await tester.pumpAndSettle();
    expect(ids(picked!), ['incline']);
  });

  testWidgets('the swap note names logged warm-ups apart', (tester) async {
    Future<void> swap({required int logged, required int warmups}) => pump(
      tester,
      ExercisePickerPage(
        max: 1,
        limit: 40,
        multiple: false,
        form: ExercisePickerForm.swap,
        exerciseId: 'bench',
        logged: logged,
        warmups: warmups,
      ),
    );

    await swap(logged: 1, warmups: 2);
    expect(
      find.text(
        '2 warm-ups and set 1 are logged; the rest move to the new exercise.',
      ),
      findsOneWidget,
    );

    await swap(logged: 0, warmups: 1);
    expect(
      find.text('1 warm-up is logged; the rest move to the new exercise.'),
      findsOneWidget,
    );
  });

  testWidgets('similar ones the search leaves out go, and their label too', (
    tester,
  ) async {
    when(() => library.state)
        .thenReturn(LibraryState(query: 'fly', results: [fly]));
    await pump(
      tester,
      const ExercisePickerPage(
        max: 1,
        limit: 40,
        multiple: false,
        form: ExercisePickerForm.swap,
        exerciseId: 'bench',
      ),
    );

    expect(find.textContaining('logged'), findsNothing);
    expect(find.text('Similar'), findsNothing);
    expect(find.text('All exercises'), findsOneWidget);
    expect(find.text('Cable Fly'), findsOneWidget);
  });

  testWidgets('replacing an exercise no longer in the library', (tester) async {
    await pump(
      tester,
      const ExercisePickerPage(
        max: 1,
        limit: 20,
        multiple: false,
        form: ExercisePickerForm.replace,
      ),
    );

    expect(find.text('Replace exercise'), findsOneWidget);
    expect(find.text('Similar'), findsNothing);
    expect(find.text('Bench Press'), findsOneWidget);
  });

  testWidgets('a search matching nothing offers to create it here', (
    tester,
  ) async {
    when(() => library.state).thenReturn(const LibraryState(query: 'landmine'));
    await pump(
      tester,
      const ExercisePickerPage(max: 3, limit: 40, multiple: true),
    );

    expect(find.text('No exercises match "landmine"'), findsOneWidget);
    expect(
      find.text('Create it as your own exercise; it is added here once saved.'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(ForgeButton, 'Create custom exercise'),
      findsOneWidget,
    );
  });
}
