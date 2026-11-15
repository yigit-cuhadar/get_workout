import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/catalogue_queries.dart';
import 'package:get_workout/features/programs/presentation/catalogue_page.dart';
import 'package:get_workout/features/programs/presentation/program_catalogue_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class _CatalogueCubit extends MockCubit<ProgramCatalogueState>
    implements ProgramCatalogueCubit {}

void main() {
  final fits = card(
    'fits',
    goal: Goal.getStronger,
    level: Level.intermediate,
    lengthWeeks: 8,
  );
  final paid = card('paid', premium: true, daysPerWeek: 4, order: 2);
  const profile = TrainingProfile(
    goal: Goal.getStronger,
    level: Level.intermediate,
    daysPerWeek: 3,
    equipment: {Equipment.dumbbell, Equipment.bench},
  );

  late _CatalogueCubit cubit;

  setUp(() {
    cubit = _CatalogueCubit();
    when(() => cubit.search(any())).thenReturn(null);
    when(cubit.clearFilters).thenReturn(null);
    sl.registerSingleton<ProgramCatalogueCubit>(cubit);
  });

  tearDown(sl.reset);

  Future<void> pump(WidgetTester tester, ProgramCatalogueState state) async {
    when(() => cubit.state).thenReturn(state);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppPreset.slate.lightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CataloguePage(),
      ),
    );
    await tester.pump();
  }

  ProgramCatalogueState ready({
    CatalogueFilter filter = const CatalogueFilter(),
    String query = '',
    bool? premium = false,
  }) => ProgramCatalogueState(
    status: ProgramCatalogueStatus.ready,
    programs: [fits, paid],
    profile: profile,
    filter: filter,
    query: query,
    premium: premium,
  );

  testWidgets('the best match, the count and every program', (tester) async {
    await pump(tester, ready());

    expect(find.text('Recommended for you'), findsOneWidget);
    expect(
      find.text(
        'Matches your goal, level, days per week and '
        'equipment',
      ),
      findsOneWidget,
    );
    expect(find.text('2 programs · 1 free'), findsOneWidget);
    expect(find.text('Program fits'), findsNWidgets(2));
    expect(find.text('Fits you'), findsNWidgets(2));
    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('3 days · Intermediate · 8 weeks'), findsNWidgets(2));
  });

  testWidgets('with Premium the count has no free part', (tester) async {
    await pump(tester, ready(premium: true));

    expect(find.text('2 programs'), findsOneWidget);
    expect(find.text('Premium'), findsNothing);
  });

  testWidgets('filters: chosen values removable, the rest with ▾', (
    tester,
  ) async {
    await pump(tester, ready(filter: const CatalogueFilter(daysPerWeek: {4})));

    expect(find.text('Only my equipment'), findsOneWidget);
    expect(find.text('Level'), findsOneWidget);
    expect(find.text('4 days'), findsOneWidget);
    expect(find.text('1 filter on'), findsOneWidget);
    expect(find.text('Recommended for you'), findsNothing);
    expect(find.text('2 programs · 1 free'), findsNothing);
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
