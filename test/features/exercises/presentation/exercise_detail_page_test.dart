import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
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
import 'package:get_workout/features/exercises/domain/exercise_animation.dart';
import 'package:get_workout/features/exercises/presentation/exercise_motion_cubit.dart';
import 'package:get_workout/features/exercises/presentation/favorites_cubit.dart';
import 'package:get_workout/features/exercises/presentation/widgets/exercise_tile.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/strength/presentation/exercise_strength_cubit.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';

import 'package:get_workout/features/analytics/domain/analytics.dart';

import '../../../fake_body_model.dart';

class _CatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class _DetailCubit extends MockCubit<ExerciseDetailState>
    implements ExerciseDetailCubit {}

class _FavoritesCubit extends MockCubit<FavoritesState>
    implements FavoritesCubit {}

class _ModelCubit extends MockCubit<BodyModelState> implements BodyModelCubit {}

class _MotionCubit extends MockCubit<ExerciseMotionState>
    implements ExerciseMotionCubit {}

class _Model extends Fake implements Model3D {}

class _Clip extends Fake implements ClipMotion {}

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _StrengthCubit extends MockCubit<ExerciseStrengthState>
    implements ExerciseStrengthCubit {}

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
  late _FavoritesCubit favorites;
  late _StrengthCubit strength;

  setUp(() {
    strength = _StrengthCubit();
    when(() => strength.state).thenReturn(const ExerciseStrengthState());
    sl.registerFactoryParam<ExerciseStrengthCubit, String, WeightUnit>(
      (_, _) => strength,
    );
    detail = _DetailCubit();
    favorites = _FavoritesCubit();
    when(() => favorites.state).thenReturn(const FavoritesState({}));
    when(() => favorites.toggle(any())).thenAnswer((_) async {});
    sl.registerFactoryParam<ExerciseDetailCubit, String, void>(
      (_, _) => detail,
    );
    registerNoMotion();
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
    final settings = _SettingsCubit();
    when(() => settings.state).thenReturn(
      const SettingsState(
        UserSettings(weightUnit: WeightUnit.kg, lengthUnit: LengthUnit.cm),
      ),
    );
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
    // The model shimmers while it loads, which never settles.
    await tester.pump(const Duration(milliseconds: 500));
  }

  // The model shimmers while it loads, which never settles.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(find.widgetWithText(Tab, tab));
    await settle(tester);
  }

  testWidgets('without an animation: no form chips, mistakes listed', (
    tester,
  ) async {
    await pump(tester, DetailReady(bench, alternatives: [dumbbell]));

    expect(find.text('Correct form'), findsNothing);
    expect(find.text('Mistake 1'), findsNothing);
    expect(find.text('Common mistakes'), findsOneWidget);
    expect(find.text('Bouncing the bar.'), findsOneWidget);
    expect(find.text('Flaring the elbows.'), findsOneWidget);
    expect(find.bySemanticsLabel('Watch mistake 1'), findsNothing);
    // How to do it is open: the steps, the mistakes and the safety line.
    expect(find.byType(BenefitList), findsNWidgets(2));
    expect(find.text('• Use a spotter.'), findsOneWidget);
    expect(find.text('Pattern'), findsNothing);
    expect(find.text('Custom'), findsNothing);
    expect(find.text('Exercise options'), findsNothing);
  });

  testWidgets('with an animation: mistakes first, played on the stage', (
    tester,
  ) async {
    await sl.unregister<ExerciseMotionCubit>();
    final motion = _MotionCubit();
    when(() => motion.state).thenReturn(
      MotionReady(
        clips: const [AnimationClip.correct(), AnimationClip.mistake(0, 0)],
        selected: 0,
        model: _Model(),
        motion: _Clip(),
      ),
    );
    when(motion.load).thenAnswer((_) async {});
    when(() => motion.select(any())).thenReturn(null);
    sl.registerFactoryParam<ExerciseMotionCubit, String, void>(
      (_, _) => motion,
    );
    await pump(tester, DetailReady(bench));

    // The correct form plays with nothing on the stage's foot.
    expect(find.bySemanticsLabel('Back to the correct form'), findsNothing);
    // Every mistake is on How to do it, first; the one with a clip plays it.
    expect(find.text('Common mistakes'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Common mistakes')).dy,
      lessThan(tester.getTopLeft(find.text('Set the bench flat.')).dy),
    );
    expect(find.text('Flaring the elbows.'), findsOneWidget);
    expect(find.bySemanticsLabel('Watch mistake 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Watch mistake 2'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Watch mistake 1'));
    await settle(tester);
    verify(() => motion.select(1)).called(1);
  });

  testWidgets('a mistake playing is named on the stage; × goes back', (
    tester,
  ) async {
    await sl.unregister<ExerciseMotionCubit>();
    final motion = _MotionCubit();
    when(() => motion.state).thenReturn(
      MotionReady(
        clips: const [AnimationClip.correct(), AnimationClip.mistake(0, 0)],
        selected: 1,
        model: _Model(),
        motion: _Clip(),
      ),
    );
    when(motion.load).thenAnswer((_) async {});
    when(() => motion.select(any())).thenReturn(null);
    sl.registerFactoryParam<ExerciseMotionCubit, String, void>(
      (_, _) => motion,
    );
    await pump(tester, DetailReady(bench));

    // On the stage's foot and in the list.
    expect(find.text('Bouncing the bar.'), findsNWidgets(2));
    await tester.tap(find.bySemanticsLabel('Back to the correct form'));
    verify(() => motion.select(0)).called(1);
  });

  testWidgets('Details holds the facts and the similar exercises', (
    tester,
  ) async {
    await pump(tester, DetailReady(bench, alternatives: [dumbbell]));
    await openTab(tester, 'Details');

    expect(find.text('Pattern'), findsOneWidget);
    expect(find.text('Logged as'), findsOneWidget);
    expect(find.text('Also called'), findsOneWidget);
    expect(find.text('Alternatives · 1'), findsOneWidget);
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
  });

  testWidgets('Performance, never done, offers Add to workout', (tester) async {
    when(() => strength.state).thenReturn(
      const ExerciseStrengthState(status: ExerciseStrengthStatus.ready),
    );
    await pump(tester, DetailReady(bench));
    await openTab(tester, 'Performance');

    expect(find.text('No sets yet'), findsOneWidget);
    expect(find.widgetWithText(ForgeButton, 'Add to workout'), findsOneWidget);
  });

  testWidgets('Performance lists the latest workouts and See progress', (
    tester,
  ) async {
    when(() => strength.state).thenReturn(
      ExerciseStrengthState(
        status: ExerciseStrengthStatus.ready,
        trained: true,
        sessions: [
          for (var i = 0; i < 7; i++)
            HistoryPoint(
              date: DateTime(2026, 11, 20 - i),
              workoutId: 'w$i',
              workoutName: 'Push $i',
            ),
        ],
      ),
    );
    await pump(tester, DetailReady(bench));
    await openTab(tester, 'Performance');

    expect(find.textContaining('Last time'), findsOneWidget);
    // The five latest; See progress opens the rest.
    expect(find.textContaining('Push 4'), findsOneWidget);
    expect(find.textContaining('Push 5'), findsNothing);
    expect(find.text('See progress'), findsOneWidget);
  });

  testWidgets('the star in the app bar makes it a favourite', (tester) async {
    await pump(tester, DetailReady(bench));

    await tester.tap(find.bySemanticsLabel('Add to favourites'));
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
    await openTab(tester, 'Details');

    expect(find.text('Variations · 4'), findsOneWidget);
    expect(find.text('See all (4)'), findsOneWidget);
    expect(find.text('Alternatives · 1'), findsOneWidget);
    expect(find.text('Variation 3'), findsOneWidget);
    expect(find.text('Variation 4'), findsNothing);
    // Variations come first.
    expect(
      tester.getTopLeft(find.text('Variations · 4')).dy,
      lessThan(tester.getTopLeft(find.text('Alternatives · 1')).dy),
    );
  });

  testWidgets('a Similar row opens its exercise', (tester) async {
    await pump(tester, DetailReady(bench, alternatives: [dumbbell]));
    await openTab(tester, 'Details');

    expect(find.textContaining('See all'), findsNothing);
    await tester.tap(find.text('Dumbbell Bench Press'));
    await settle(tester);
    expect(find.text('Opened dumbbell'), findsOneWidget);
  });

  testWidgets('See all opens its group; a row opens it', (tester) async {
    final variations = [
      for (var i = 1; i <= 4; i++) exercise('v$i', name: 'Variation $i'),
    ];
    await pump(
      tester,
      DetailReady(bench, variations: variations, alternatives: [dumbbell]),
    );
    await openTab(tester, 'Details');

    await tester.tap(find.text('See all (4)'));
    await settle(tester);
    final sheet = find.byType(ForgeBottomSheet);
    for (final name in ['Variations · 4', 'Variation 1', 'Variation 4']) {
      expect(
        find.descendant(of: sheet, matching: find.text(name)),
        findsOneWidget,
        reason: name,
      );
    }
    expect(
      find.descendant(of: sheet, matching: find.text('Dumbbell Bench Press')),
      findsNothing,
    );

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
    await openTab(tester, 'Details');
    expect(find.textContaining('Variations'), findsNothing);
    expect(find.textContaining('Alternatives'), findsNothing);
  });

  testWidgets('a row says Easier or Harder when its level differs', (
    tester,
  ) async {
    await pump(
      tester,
      DetailReady(
        exercise('mid', name: 'Middle', level: Level.intermediate),
        variations: [
          exercise('easy', name: 'Easy one'),
          exercise('same', name: 'Same one', level: Level.intermediate),
          exercise('hard', name: 'Hard one', level: Level.advanced),
        ],
      ),
    );
    await openTab(tester, 'Details');

    expect(find.text('Easier'), findsOneWidget);
    expect(find.text('Harder'), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Same one'),
          matching: find.byType(ExerciseTile),
        ),
        matching: find.byType(ForgeTag),
      ),
      findsNothing,
    );
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
    expect(find.text('Add to favourites'), findsNothing);
    expect(find.text('Edit'), findsNothing);
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
