import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/catalogue_queries.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/presentation/catalogue_page.dart';
import 'package:get_workout/features/programs/presentation/program_catalogue_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class _CatalogueCubit extends MockCubit<ProgramCatalogueState>
    implements ProgramCatalogueCubit {}

class _ListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

void main() {
  final fits = card(
    'fits',
    goal: Goal.getStronger,
    level: Level.intermediate,
    lengthWeeks: 8,
  );
  final paid = card('paid', premium: true, daysPerWeek: 4, order: 2);
  // Two days more than the user's: never recommended.
  final far = card('far', daysPerWeek: 5, order: 3);
  const profile = TrainingProfile(
    goal: Goal.getStronger,
    level: Level.intermediate,
    daysPerWeek: 3,
    equipment: {Equipment.dumbbell, Equipment.bench},
  );

  late _CatalogueCubit cubit;
  late _ListCubit list;

  setUp(() {
    cubit = _CatalogueCubit();
    list = _ListCubit();
    when(() => list.state).thenReturn(const ProgramListState());
    when(() => cubit.search(any())).thenReturn(null);
    when(cubit.clearFilters).thenReturn(null);
    when(cubit.openCatalogue).thenReturn(null);
    sl
      ..registerSingleton<ProgramCatalogueCubit>(cubit)
      ..registerSingleton<ProgramListCubit>(list);
  });

  tearDown(sl.reset);

  Future<void> pump(WidgetTester tester, ProgramCatalogueState state) async {
    when(() => cubit.state).thenReturn(state);
    final router = GoRouter(
      initialLocation: '/catalogue',
      routes: [
        GoRoute(path: '/catalogue', builder: (_, _) => const CataloguePage()),
        GoRoute(
          path: '/:a/:b',
          builder: (_, state) => Text('at ${state.uri.path}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppPreset.slate.lightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pump();
  }

  /// The user's copy c1 of [fits], active in its second week.
  void copyActive({bool finished = false}) => when(() => list.state).thenReturn(
    ProgramListState(
      status: ProgramListStatus.ready,
      programs: [
        Program(
          id: 'c1',
          name: 'Program fits',
          origin: ProgramOrigin.catalog,
          sourceId: 'fits',
          lengthWeeks: 8,
          days: program().days,
        ),
      ],
      active: ActiveProgram(
        programId: 'c1',
        schedule: const {1: 0, 4: 1},
        nextDayIndex: 0,
        nextDate: CalendarDate(2026, 11, 12),
        startedAt: DateTime(2026, 11, 2),
      ),
      week: 2,
      finished: finished,
    ),
  );

  ProgramCatalogueState ready({
    CatalogueFilter filter = const CatalogueFilter(),
    String query = '',
    bool? premium = false,
  }) => ProgramCatalogueState(
    status: ProgramCatalogueStatus.ready,
    programs: [fits, paid, far],
    profile: profile,
    filter: filter,
    query: query,
    premium: premium,
  );

  testWidgets('opening the page chooses the default filter', (tester) async {
    await pump(tester, ready());

    verify(cubit.openCatalogue).called(1);
  });

  testWidgets('the recommendations, the count, then the other programs', (
    tester,
  ) async {
    await pump(tester, ready());

    expect(find.text('Recommended for you'), findsOneWidget);
    // Why they are recommended is said once, not on each row.
    expect(
      find.text('Picked for your goal, level, days per week and equipment'),
      findsOneWidget,
    );
    expect(find.textContaining('Matches your'), findsNothing);
    expect(find.text('3 programs · 2 free'), findsOneWidget);
    expect(find.text('All programs'), findsOneWidget);
    // Each program once: the two recommended are not repeated below.
    for (final name in ['Program fits', 'Program paid', 'Program far']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Fits you'), findsOneWidget);
    expect(find.text('Premium'), findsOneWidget);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Program fits'), lessThan(top('Program paid')));
    expect(top('Program paid'), lessThan(top('3 programs · 2 free')));
    expect(top('3 programs · 2 free'), lessThan(top('All programs')));
    expect(top('All programs'), lessThan(top('Program far')));
  });

  testWidgets('the default filter keeps the recommendations and counts', (
    tester,
  ) async {
    await pump(
      tester,
      ready(
        filter: const CatalogueFilter(profiles: {EquipmentProfile.dumbbells}),
      ),
    );

    expect(find.text('1 filter on'), findsOneWidget);
    expect(find.text('Recommended for you'), findsOneWidget);
    expect(find.text('3 programs · 2 free'), findsOneWidget);
    // The chosen value leads the chips.
    expect(
      tester.getTopLeft(find.text('Dumbbells and a bench')).dx,
      lessThan(tester.getTopLeft(find.text('Only my equipment')).dx),
    );
    expect(find.text('Equipment'), findsNothing);

    await tester.tap(find.text('Clear'));
    verify(cubit.clearFilters).called(1);
  });

  testWidgets('no recommendations, no section', (tester) async {
    await pump(
      tester,
      ProgramCatalogueState(
        status: ProgramCatalogueStatus.ready,
        programs: [far],
        profile: profile,
        premium: false,
      ),
    );

    expect(find.text('Recommended for you'), findsNothing);
    expect(find.text('All programs'), findsNothing);
    expect(find.text('Program far'), findsOneWidget);
  });

  testWidgets('an active copy comes first and opens the copy; all programs '
      'follow', (tester) async {
    copyActive();
    await pump(tester, ready());

    expect(find.text('Your active program'), findsOneWidget);
    expect(find.text('Week 2 of 8 · opens your copy'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('All programs'), findsOneWidget);
    // Lifted out of the list below and not recommended again: shown once,
    // with its week in place of its facts; the next best takes its place.
    expect(find.text('Program fits'), findsOneWidget);
    expect(find.text('3 days · Intermediate · 8 weeks'), findsNothing);
    expect(find.text('Recommended for you'), findsOneWidget);
    expect(find.text('Program paid'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Your active program')).dy,
      lessThan(tester.getTopLeft(find.text('All programs')).dy),
    );

    await tester.tap(find.text('Week 2 of 8 · opens your copy'));
    await tester.pumpAndSettle();
    expect(find.text('at /programs/c1'), findsOneWidget);
  });

  testWidgets('a finished copy says so', (tester) async {
    copyActive(finished: true);
    await pump(tester, ready());

    expect(find.text('Finished · opens your copy'), findsOneWidget);
  });

  testWidgets('while searching the copy is not lifted out', (tester) async {
    copyActive();
    await pump(tester, ready(query: 'fits'));

    expect(find.text('Your active program'), findsNothing);
    expect(find.text('All programs'), findsNothing);
    expect(find.text('Program fits'), findsOneWidget);
  });

  testWidgets('with Premium the count has no free part', (tester) async {
    await pump(tester, ready(premium: true));

    expect(find.text('3 programs'), findsOneWidget);
    expect(find.text('Premium'), findsNothing);
  });

  testWidgets('filters: chosen values first and removable, the rest with ▾; '
      'any filter but the default hides the recommendations', (tester) async {
    await pump(tester, ready(filter: const CatalogueFilter(daysPerWeek: {4})));

    expect(find.text('Only my equipment'), findsOneWidget);
    expect(find.text('Level'), findsOneWidget);
    expect(find.text('Days per week'), findsNothing);
    expect(
      tester.getTopLeft(find.text('4 days')).dx,
      lessThan(tester.getTopLeft(find.text('Only my equipment')).dx),
    );
    expect(find.text('1 filter on'), findsOneWidget);
    expect(find.text('Recommended for you'), findsNothing);
    expect(find.text('3 programs · 2 free'), findsNothing);
  });

  testWidgets('a search finding nothing offers to clear it', (tester) async {
    await pump(tester, ready(query: 'zzz'));

    expect(find.text('No programs match'), findsOneWidget);
    expect(find.text('Try another name.'), findsOneWidget);
    await tester.tap(find.text('Clear search'));
    verify(() => cubit.search('')).called(greaterThanOrEqualTo(1));
  });

  testWidgets('filters finding nothing offer to clear them', (tester) async {
    await pump(tester, ready(filter: const CatalogueFilter(daysPerWeek: {6})));

    expect(find.text('Remove a filter to see more programs.'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    verify(cubit.clearFilters).called(1);
  });

  testWidgets('offline keeps the search over the error', (tester) async {
    await pump(
      tester,
      const ProgramCatalogueState(status: ProgramCatalogueStatus.offline),
    );

    expect(find.text('Search programs'), findsOneWidget);
    expect(find.text("Couldn't load programs"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
