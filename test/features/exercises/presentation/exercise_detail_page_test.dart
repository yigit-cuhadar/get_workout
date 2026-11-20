import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_detail_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_detail_page.dart';
import 'package:get_workout/features/exercises/presentation/exercise_notes_cubit.dart';
import 'package:get_workout/features/exercises/presentation/favorites_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';

import 'package:get_workout/features/analytics/domain/analytics.dart';

class _CatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class _DetailCubit extends MockCubit<ExerciseDetailState>
    implements ExerciseDetailCubit {}

class _NotesCubit extends MockCubit<ExerciseNotesState>
    implements ExerciseNotesCubit {}

class _FavoritesCubit extends MockCubit<FavoritesState>
    implements FavoritesCubit {}

class _ModelCubit extends MockCubit<BodyModelState> implements BodyModelCubit {}

void main() {
  final bench = exercise(
    'bench',
    name: 'Bench Press',
    aliases: ['Flat bench'],
    translations: {
      'en': const ExerciseText(
        name: 'Bench Press',
        aliases: ['Flat bench'],
        setup: ['Set the bench flat.'],
        mistakes: ['Bouncing the bar.', 'Flaring the elbows.'],
        safety: 'Use a spotter.',
      ),
    },
  );
  final dumbbell = exercise('dumbbell', name: 'Dumbbell Bench Press');
  final custom = Exercise.custom(
    id: 'custom_cable',
    name: 'Bench Press (cable)',
    loggingType: LoggingType.weightReps,
    mainMuscles: const [Muscle.pec],
    equipment: const [Equipment.cable],
    note: 'Third hole.',
  );

  late _DetailCubit detail;
  late _NotesCubit notes;
  late _FavoritesCubit favorites;

  setUp(() {
    detail = _DetailCubit();
    notes = _NotesCubit();
    when(() => notes.state).thenReturn(const ExerciseNotesState({}));
    when(() => notes.save(any(), any())).thenAnswer((_) async => null);
    favorites = _FavoritesCubit();
    when(() => favorites.state).thenReturn(const FavoritesState({}));
    when(() => favorites.toggle(any())).thenAnswer((_) async {});
    sl
      ..registerFactoryParam<ExerciseDetailCubit, String, void>(
        (_, _) => detail,
      )
      ..registerSingleton<ExerciseNotesCubit>(notes);
  });

  tearDown(sl.reset);

  Future<void> pump(WidgetTester tester, ExerciseDetailState state) async {
    tester.view
      ..physicalSize = const Size(1500, 6000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    when(() => detail.state).thenReturn(state);
    final catalogue = _CatalogueCubit();
    when(() => catalogue.state).thenReturn(CatalogueReady([bench, custom]));
    final model = _ModelCubit();
    when(() => model.state).thenReturn(const BodyModelLoading());
    when(model.load).thenAnswer((_) async {});
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => ExerciseDetailPage(
            from: ExerciseViewSource.library,
            exerciseId: 'bench',
            exerciseRoute: (id) => '/$id',
          ),
        ),
        GoRoute(
          path: '/:id',
          builder: (_, state) => Text('Opened ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ExerciseCatalogueCubit>.value(value: catalogue),
          BlocProvider<FavoritesCubit>.value(value: favorites),
          BlocProvider<BodyModelCubit>.value(value: model),
        ],
        child: MaterialApp.router(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    // The model shimmers while it loads, which never settles.
    await tester.pump(const Duration(milliseconds: 500));
  }

  // The model shimmers while it loads, which never settles.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('a catalogue exercise: facts, steps, bullets and similar', (
    tester,
  ) async {
    await pump(tester, DetailReady(bench, alternatives: [dumbbell]));

    expect(find.text('Pattern'), findsOneWidget);
    expect(find.text('Logged as'), findsOneWidget);
    expect(find.text('Also called'), findsOneWidget);
    expect(find.byType(BenefitList), findsOneWidget);
    expect(find.text('• Bouncing the bar.'), findsOneWidget);
    expect(find.text('• Use a spotter.'), findsOneWidget);
    expect(find.text('Similar exercises'), findsOneWidget);
    expect(find.text('Alternatives · 1'), findsOneWidget);
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    expect(find.text('Custom'), findsNothing);
    expect(find.text('Exercise options'), findsNothing);
  });

  testWidgets('the ⋯ menu makes it a favourite', (tester) async {
    await pump(tester, DetailReady(bench));

    await tester.tap(find.bySemanticsLabel('Exercise options'));
    await settle(tester);
    await tester.tap(find.text('Add to favourites'));
    verify(() => favorites.toggle('bench')).called(1);
  });

  testWidgets('Similar shows each group with its count and first three', (
    tester,
  ) async {
    final variations = [
      for (var i = 1; i <= 4; i++) exercise('v$i', name: 'Variation $i'),
    ];
    await pump(
      tester,
      DetailReady(bench, variations: variations, alternatives: [dumbbell]),
    );

    final card = find.ancestor(
      of: find.text('Similar exercises'),
      matching: find.byType(SectionCard),
    );
    expect(find.descendant(of: card, matching: find.text('5')), findsOneWidget);
    expect(find.text('Variations · 4'), findsOneWidget);
    expect(find.text('Alternatives · 1'), findsOneWidget);
    expect(find.text('Variation 3'), findsOneWidget);
    expect(find.text('Variation 4'), findsNothing);
    // Variations come first.
    expect(
      tester.getTopLeft(find.text('Variations · 4')).dy,
      lessThan(tester.getTopLeft(find.text('Alternatives · 1')).dy),
    );
  });

  testWidgets('the Similar card opens every one; a row opens it', (
    tester,
  ) async {
    final variations = [
      for (var i = 1; i <= 4; i++) exercise('v$i', name: 'Variation $i'),
    ];
    await pump(
      tester,
      DetailReady(bench, variations: variations, alternatives: [dumbbell]),
    );

    await tester.tap(find.text('Similar exercises'));
    await settle(tester);
    final sheet = find.byType(ForgeBottomSheet);
    for (final name in [
      'Variations · 4',
      'Variation 4',
      'Alternatives · 1',
      'Dumbbell Bench Press',
    ]) {
      expect(
        find.descendant(of: sheet, matching: find.text(name)),
        findsOneWidget,
        reason: name,
      );
    }

    await tester.tap(
      find.descendant(of: sheet, matching: find.text('Variation 4')),
    );
    await settle(tester);
    expect(find.byType(ForgeBottomSheet), findsNothing);
    expect(find.text('Opened v4'), findsOneWidget);
  });

  testWidgets('no Similar card without variations or alternatives', (
    tester,
  ) async {
    await pump(tester, DetailReady(bench));
    expect(find.text('Similar exercises'), findsNothing);
  });

  testWidgets('the ⋯ menu adds to a workout or a program; no bottom bar', (
    tester,
  ) async {
    await pump(tester, DetailReady(bench));

    expect(find.byType(ForgeBottomActionBar), findsNothing);
    await tester.tap(find.bySemanticsLabel('Exercise options'));
    await settle(tester);
    expect(
      tester.getTopLeft(find.text('Add to workout')).dy,
      lessThan(tester.getTopLeft(find.text('Add to program')).dy),
    );
    expect(find.text('Add to favourites'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('without a note, Your note offers Add; Save stores it', (
    tester,
  ) async {
    await pump(tester, DetailReady(bench));

    expect(find.text('Your note'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(SectionCard), matching: find.text('Add')),
    );
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Grip on the rings.');
    await tester.tap(find.text('Save'));
    await settle(tester);

    verify(() => notes.save('bench', 'Grip on the rings.')).called(1);
  });

  testWidgets('a note shows with Edit', (tester) async {
    when(() => notes.state)
        .thenReturn(const ExerciseNotesState({'bench': 'Grip on the rings.'}));
    await pump(tester, DetailReady(bench));

    expect(find.text('Grip on the rings.'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('a custom exercise: its tag, equipment, note and ⋯', (
    tester,
  ) async {
    await pump(tester, DetailReady(custom));

    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Logged as weight × reps'), findsOneWidget);
    expect(find.text('Equipment'), findsOneWidget);
    expect(find.text('Level'), findsNothing);
    expect(find.text('Third hole.'), findsOneWidget);
    expect(find.text('Your note'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Exercise options'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Delete this exercise?'), findsOneWidget);
    expect(find.byType(ForgeDialog), findsOneWidget);
  });

  testWidgets('not found is one line, without a title', (tester) async {
    await pump(tester, const DetailNotFound());

    expect(find.text('This exercise is no longer available.'), findsOneWidget);
    expect(find.text('Exercise not found'), findsNothing);
  });
}
