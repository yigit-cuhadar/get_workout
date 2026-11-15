import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/catalogue_program.dart';
import 'package:get_workout/features/programs/domain/catalogue_queries.dart';
import 'package:get_workout/features/programs/presentation/catalogue_detail_cubit.dart';
import 'package:get_workout/features/programs/presentation/catalogue_detail_page.dart';
import 'package:get_workout/features/programs/presentation/premium_prompt.dart';
import 'package:get_workout/features/programs/presentation/program_catalogue_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class _DetailCubit extends MockCubit<CatalogueDetailState>
    implements CatalogueDetailCubit {}

class _CatalogueCubit extends MockCubit<ProgramCatalogueState>
    implements ProgramCatalogueCubit {}

class _ExercisesCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class _ModelCubit extends MockCubit<BodyModelState> implements BodyModelCubit {}

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

void main() {
  const free = CatalogueProgram(
    id: 'ppl',
    premium: false,
    level: Level.intermediate,
    goal: Goal.buildMuscle,
    daysPerWeek: 2,
    lengthWeeks: 8,
    minutes: (min: 45, max: 60),
    equipmentProfile: EquipmentProfile.fullGym,
    order: 1,
    l10n: {'en': CatalogueText(name: 'Push Pull', summary: 'A classic split.')},
  );
  const paid = CatalogueProgram(
    id: 'ul',
    premium: true,
    level: Level.advanced,
    goal: Goal.getStronger,
    daysPerWeek: 2,
    lengthWeeks: 12,
    minutes: (min: 70, max: 70),
    dayList: [
      CatalogueDay(name: 'Upper A', exercises: 6),
      CatalogueDay(name: 'Lower A', exercises: 5),
    ],
    equipmentProfile: EquipmentProfile.fullGym,
    order: 2,
    l10n: {'en': CatalogueText(name: 'Upper Lower', summary: 'Heavy days.')},
  );
  final days = program().days;

  late _DetailCubit detail;
  late int paywalls;

  setUp(() {
    paywalls = 0;
    detail = _DetailCubit();
    when(() => detail.copy(any(), weekdays: any(named: 'weekdays')))
        .thenAnswer((_) async {});
    when(() => detail.existingCopyId).thenReturn(null);
    when(() => detail.activeProgramName).thenReturn(null);
    sl
      ..registerFactoryParam<CatalogueDetailCubit, String, String>(
        (_, _) => detail,
      )
      ..registerSingleton(PremiumPrompt((_) => paywalls++));
  });

  setUpAll(() => registerFallbackValue(CopyIntent.keep));

  tearDown(sl.reset);

  Future<void> pump(WidgetTester tester, CatalogueDetailState state) async {
    tester.view
      ..physicalSize = const Size(1200, 4800)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    when(() => detail.state).thenReturn(state);
    final catalogue = _CatalogueCubit();
    when(() => catalogue.state).thenReturn(
      const ProgramCatalogueState(
        status: ProgramCatalogueStatus.ready,
        profile: TrainingProfile(
          goal: Goal.buildMuscle,
          level: Level.intermediate,
          daysPerWeek: 2,
        ),
      ),
    );
    final exercises = _ExercisesCubit();
    when(() => exercises.state).thenReturn(const CatalogueLoading());
    final model = _ModelCubit();
    when(() => model.state).thenReturn(const BodyModelLoading());
    when(model.load).thenAnswer((_) async {});
    final settings = _SettingsCubit();
    when(() => settings.state)
        .thenReturn(SettingsState(UserSettings.defaultsFor(null)));
    Widget location(BuildContext _, GoRouterState state) =>
        Text('at ${state.uri.path}');
    final router = GoRouter(
      initialLocation: '/p',
      routes: [
        GoRoute(
          path: '/p',
          builder: (_, _) => const CatalogueDetailPage(id: 'x'),
        ),
        GoRoute(
          path: '/:a',
          builder: location,
          routes: [
            GoRoute(
              path: ':b',
              builder: location,
              routes: [GoRoute(path: ':c', builder: location)],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ProgramCatalogueCubit>.value(value: catalogue),
          BlocProvider<ExerciseCatalogueCubit>.value(value: exercises),
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
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  CatalogueDetailState ready({UseStatus useStatus = UseStatus.ready}) =>
      CatalogueDetailState(
        status: CatalogueDetailStatus.ready,
        program: free,
        days: days,
        useStatus: useStatus,
      );

  testWidgets('a free program: tags, facts, weekly sets, days and Start', (
    tester,
  ) async {
    await pump(tester, ready());

    expect(find.text('Push Pull'), findsOneWidget);
    expect(find.text('Fits you'), findsOneWidget);
    expect(find.text('2 a week'), findsOneWidget);
    expect(find.text('8 weeks · 45–60 min'), findsOneWidget);
    expect(find.text('Weekly sets in this program'), findsOneWidget);
    expect(find.text('Day 1 · Upper'), findsOneWidget);
    expect(find.text('2 exercises'), findsNWidgets(2));
    expect(find.text('Start this program'), findsOneWidget);
  });

  testWidgets('Start makes no copy until the days are picked', (tester) async {
    await pump(tester, ready());

    await tester.tap(find.text('Start this program'));
    await settle(tester);
    expect(find.text('Pick 2 training days'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    verifyNever(() => detail.copy(any(), weekdays: any(named: 'weekdays')));

    await tester.tap(find.text('Start this program'));
    await settle(tester);
    await tester.tap(find.text('Start program'));
    await settle(tester);
    verify(
      () => detail.copy(CopyIntent.start, weekdays: any(named: 'weekdays')),
    ).called(1);
  });

  testWidgets('the user\'s copy is offered first', (tester) async {
    when(() => detail.existingCopyId).thenReturn('mine');
    await pump(tester, ready());

    await tester.tap(find.text('Start this program'));
    await settle(tester);
    expect(find.text('You already have this program'), findsOneWidget);
    await tester.tap(find.text('Open my copy'));
    await settle(tester);
    expect(find.text('at /programs/mine'), findsOneWidget);
  });

  testWidgets('⋯ › Duplicate copies to edit', (tester) async {
    await pump(tester, ready());

    await tester.tap(find.bySemanticsLabel('Program options'));
    await settle(tester);
    await tester.tap(find.text('Duplicate'));
    await settle(tester);
    verify(() => detail.copy(CopyIntent.edit)).called(1);
  });

  testWidgets('a copy to edit opens the builder', (tester) async {
    whenListen(
      detail,
      Stream.fromIterable([
        ready().copyWith(
          copyStatus: CopyStatus.copied,
          copyIntent: () => CopyIntent.edit,
          copyId: () => 'c1',
        ),
      ]),
      initialState: ready(),
    );
    when(detail.copyHandled).thenReturn(null);
    await pump(tester, ready());
    await settle(tester);

    expect(find.text('at /programs/c1/edit'), findsOneWidget);
  });

  testWidgets('a locked program lists its days and offers Premium', (
    tester,
  ) async {
    await pump(
      tester,
      const CatalogueDetailState(
        status: CatalogueDetailStatus.locked,
        program: paid,
      ),
    );

    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('12 weeks · ~70 min'), findsOneWidget);
    expect(find.text('Day 1 · Upper A'), findsOneWidget);
    expect(find.text('6 exercises'), findsOneWidget);
    expect(find.text('Weekly sets in this program'), findsNothing);
    expect(find.bySemanticsLabel('Program options'), findsNothing);

    await tester.tap(find.text('Get Premium to start'));
    expect(paywalls, 1);
  });

  testWidgets('a missing exercise disables Start and says why', (tester) async {
    await pump(tester, ready(useStatus: UseStatus.exercisesMissing));

    expect(
      find.text(
        'This program uses an exercise that is no longer available, '
        "so it can't be added.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Start this program'));
    await settle(tester);
    expect(find.text('Pick 2 training days'), findsNothing);
  });

  testWidgets('unlocking shows the notice with Retry', (tester) async {
    await pump(
      tester,
      const CatalogueDetailState(
        status: CatalogueDetailStatus.unlocking,
        program: paid,
      ),
    );

    expect(find.text('Unlocking this program'), findsOneWidget);
    expect(
      find.text('Premium is active. This takes a moment.'),
      findsOneWidget,
    );
    expect(find.text('Start this program'), findsNothing);
  });

  testWidgets('offline and not found', (tester) async {
    await pump(
      tester,
      const CatalogueDetailState(status: CatalogueDetailStatus.offline),
    );
    expect(
      find.text(
        "You're offline. Connect once to load the ready-made "
        'programs.',
      ),
      findsOneWidget,
    );

    await pump(
      tester,
      const CatalogueDetailState(status: CatalogueDetailStatus.notFound),
    );
    expect(find.text('This program is no longer available.'), findsOneWidget);
  });
}
