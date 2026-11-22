import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/analytics/domain/analytics.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/catalogue_program.dart';
import 'package:get_workout/features/programs/domain/catalogue_queries.dart';
import 'package:get_workout/features/programs/presentation/catalogue_detail_cubit.dart';
import 'package:get_workout/features/programs/presentation/premium_prompt.dart';
import 'package:get_workout/features/programs/presentation/program_catalogue_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_suggestion_page.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../fake_analytics.dart';
import 'fixtures.dart';

class _CatalogueCubit extends MockCubit<ProgramCatalogueState>
    implements ProgramCatalogueCubit {}

class _DetailCubit extends MockCubit<CatalogueDetailState>
    implements CatalogueDetailCubit {}

void main() {
  // The best match for the profile below, and premium.
  final paid = card(
    'paid',
    premium: true,
    goal: Goal.getStronger,
    level: Level.intermediate,
    daysPerWeek: 4,
    profile: EquipmentProfile.fullGym,
  );
  // One level below and a related goal: matches only the days and the
  // equipment.
  final free = card(
    'free',
    daysPerWeek: 4,
    profile: EquipmentProfile.fullGym,
    order: 2,
  );
  final profile = TrainingProfile(
    goal: Goal.getStronger,
    level: Level.intermediate,
    daysPerWeek: 4,
    equipment: EquipmentProfile.fullGym.equipment,
  );

  late _CatalogueCubit catalogue;
  late _DetailCubit detail;
  late StreamController<CatalogueDetailState> details;
  late List<bool> paywallAnswers;
  late int paywalls;
  late int onboardingPaywalls;

  setUpAll(() => registerFallbackValue(CopyIntent.keep));

  setUp(() {
    paywalls = 0;
    onboardingPaywalls = 0;
    paywallAnswers = [];
    catalogue = _CatalogueCubit();
    detail = _DetailCubit();
    details = StreamController.broadcast();
    when(() => detail.existingCopyId).thenReturn(null);
    when(() => detail.copy(any())).thenAnswer((_) async {});
    when(detail.copyHandled).thenReturn(null);
    sl
      ..registerSingleton<ProgramCatalogueCubit>(catalogue)
      ..registerFactoryParam<CatalogueDetailCubit, String, String>(
        (_, _) => detail,
      )
      ..registerSingleton(
        PremiumPrompt((_) async {
          paywalls++;
          return paywallAnswers.removeAt(0);
        }),
      );
  });

  tearDown(() async {
    await details.close();
    await sl.reset();
  });

  Future<void> pump(
    WidgetTester tester, {
    required List<CatalogueProgram> programs,
    required CatalogueDetailState detailState,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    when(() => catalogue.state).thenReturn(
      ProgramCatalogueState(
        status: ProgramCatalogueStatus.ready,
        programs: programs,
        profile: profile,
        premium: false,
      ),
    );
    whenListen(detail, details.stream, initialState: detailState);
    Widget location(BuildContext _, GoRouterState state) =>
        Text('at ${state.uri}');
    final router = GoRouter(
      initialLocation: '/suggestion',
      routes: [
        GoRoute(
          path: '/suggestion',
          builder: (_, _) => ProgramSuggestionPage(
            beforeLeaving: (_) async => onboardingPaywalls++,
          ),
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
      RepositoryProvider<Analytics>.value(
        value: fakeAnalytics(),
        child: MaterialApp.router(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  CatalogueDetailState locked() =>
      CatalogueDetailState(status: CatalogueDetailStatus.locked, program: paid);

  CatalogueDetailState ready(CatalogueProgram program) => CatalogueDetailState(
    status: CatalogueDetailStatus.ready,
    program: program,
    useStatus: UseStatus.ready,
  );

  testWidgets('the best match is suggested even when premium, tagged so', (
    tester,
  ) async {
    await pump(tester, programs: [free, paid], detailState: locked());

    expect(find.text('Program paid'), findsOneWidget);
    expect(find.text('Program free'), findsNothing);
    expect(find.text('Recommended for you'), findsOneWidget);
    expect(find.text('Recommended for you · free'), findsNothing);
    final tag = find.widgetWithText(ForgeTag, 'Premium');
    expect(tester.widget<ForgeTag>(tag).kind, ForgeTagKind.premium);
    expect(
      find.text(
        'You want to get stronger, train 4 days and use a full gym. '
        'For paid.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a free suggestion says so, and why names only what matches', (
    tester,
  ) async {
    await pump(tester, programs: [free], detailState: ready(free));

    expect(find.text('Recommended for you · free'), findsOneWidget);
    expect(find.widgetWithText(ForgeTag, 'Premium'), findsNothing);
    expect(
      find.text('You want to train 4 days and use a full gym. For free.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Start this program'));
    verify(() => detail.copy(CopyIntent.keep)).called(1);
    expect(paywalls, 0);
  });

  testWidgets('Start on a premium program opens the paywall; closed, the '
      'suggestion is passed without the onboarding paywall', (tester) async {
    paywallAnswers = [false];
    await pump(tester, programs: [paid], detailState: locked());

    await tester.tap(find.text('Start this program'));
    await tester.pumpAndSettle();

    expect(paywalls, 1);
    expect(find.text('at /today'), findsOneWidget);
    expect(onboardingPaywalls, 0);
    verifyNever(() => detail.copy(any()));
  });

  testWidgets('subscribed on that paywall, the program is saved once it '
      'unlocks and opens', (tester) async {
    paywallAnswers = [true];
    await pump(tester, programs: [paid], detailState: locked());

    await tester.tap(find.text('Start this program'));
    // Start spins until the program unlocks.
    await tester.pump();
    await tester.pump();
    expect(paywalls, 1);
    expect(
      tester
          .widget<ForgeButton>(
            find.widgetWithText(ForgeButton, 'Start this program'),
          )
          .loading,
      isTrue,
    );
    verifyNever(() => detail.copy(any()));

    details.add(ready(paid));
    await tester.pumpAndSettle();
    verify(() => detail.copy(CopyIntent.keep)).called(1);

    details.add(
      ready(paid).copyWith(
        copyStatus: CopyStatus.copied,
        copyIntent: () => CopyIntent.keep,
        copyId: () => 'c1',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('at /programs/c1?created=true&from=onboarding'), findsOne);
    // Leaving as Start does: the onboarding paywall's turn (not due for a
    // subscriber).
    expect(onboardingPaywalls, 1);
  });

  testWidgets('nothing to suggest goes straight to Today', (tester) async {
    await pump(
      tester,
      programs: [card('home', profile: EquipmentProfile.homeGym)],
      detailState: locked(),
    );

    expect(find.text('at /today'), findsOneWidget);
    expect(onboardingPaywalls, 1);
  });
}
