import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/domain/exercise_queries.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/exercises/presentation/favorites_cubit.dart';
import 'package:get_workout/features/exercises/presentation/library_cubit.dart';
import 'package:get_workout/features/exercises/presentation/widgets/library_list_view.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';

class _CatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class _LibraryCubit extends MockCubit<LibraryState> implements LibraryCubit {}

class _FavoritesCubit extends MockCubit<FavoritesState>
    implements FavoritesCubit {}

void main() {
  final all = [
    for (var i = 0; i < 40; i++) exercise('e$i', name: 'Exercise $i'),
  ];

  Future<void> pump(
    WidgetTester tester,
    LibraryState state, {
    Muscle? sectionsFor,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final catalogue = _CatalogueCubit();
    when(() => catalogue.state).thenReturn(CatalogueReady(all));
    final library = _LibraryCubit();
    when(() => library.state).thenReturn(state);
    final favorites = _FavoritesCubit();
    when(() => favorites.state).thenReturn(const FavoritesState({}));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ExerciseCatalogueCubit>.value(value: catalogue),
          BlocProvider<LibraryCubit>.value(value: library),
          BlocProvider<FavoritesCubit>.value(value: favorites),
        ],
        child: MaterialApp(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: LibraryListView(sectionsFor: sectionsFor)),
        ),
      ),
    );
    await tester.pump();
  }

  ForgeSearchField field(WidgetTester tester) =>
      tester.widget<ForgeSearchField>(find.byType(ForgeSearchField));

  Future<void> scrollDown(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
  }

  testWidgets('the filters scroll away under the pinned search, which then '
      'names them; a tap on that goes back to the top', (tester) async {
    await pump(
      tester,
      LibraryState(
        results: all,
        filter: const LibraryFilter(
          onlyFavorites: true,
          equipment: {Equipment.dumbbell, Equipment.bench},
        ),
      ),
    );
    final searchTop = tester.getTopLeft(find.byType(ForgeSearchField)).dy;
    expect(find.text('Clear all'), findsOneWidget);
    expect(find.text('40 exercises'), findsOneWidget);
    expect(field(tester).summary, isNull);
    expect(field(tester).heroTag, isNull);

    await scrollDown(tester);
    expect(tester.getTopLeft(find.byType(ForgeSearchField)).dy, searchTop);
    expect(find.text('Clear all'), findsNothing);
    expect(find.text('40 exercises'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ForgeSearchField),
        matching: find.text('3 filters'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('3 filters'));
    await tester.pumpAndSettle();
    expect(find.text('Clear all'), findsOneWidget);
    expect(field(tester).summary, isNull);
  });

  testWidgets('without filters nothing is named once the count is gone', (
    tester,
  ) async {
    await pump(tester, LibraryState(results: all));

    await scrollDown(tester);
    expect(find.text('40 exercises'), findsNothing);
    expect(field(tester).summary, isNull);
  });

  testWidgets('a muscle\'s sections scroll away too and name the muscle '
      'and the section shown', (tester) async {
    final sections = exercisesWorking(Muscle.pec, all);
    await pump(
      tester,
      LibraryState(
        results: all,
        filter: const LibraryFilter(muscles: {Muscle.pec}),
        muscleExercises: sections,
      ),
      sectionsFor: Muscle.pec,
    );
    expect(find.text('Main · 40'), findsOneWidget);

    await scrollDown(tester);
    expect(find.text('Main · 40'), findsNothing);
    expect(find.text('Chest · Main'), findsOneWidget);
  });
}
