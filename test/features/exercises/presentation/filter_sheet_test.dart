import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/core/widgets/check_sheet.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:get_workout/features/exercises/presentation/library_cubit.dart';
import 'package:get_workout/features/exercises/presentation/widgets/filter_sheet.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures.dart';

class _LibraryCubit extends MockCubit<LibraryState> implements LibraryCubit {}

class _EquipmentCubit extends MockCubit<EquipmentState>
    implements EquipmentCubit {}

void main() {
  late _LibraryCubit library;
  late _EquipmentCubit equipment;

  setUp(() {
    library = _LibraryCubit();
    equipment = _EquipmentCubit();
    when(() => equipment.state)
        .thenReturn(const EquipmentState({Equipment.barbell, Equipment.bench}));
    when(() => equipment.save(any())).thenAnswer((_) async {});
  });

  LibraryState state({LibraryFilter filter = const LibraryFilter()}) =>
      LibraryState(
        filter: filter,
        results: [exercise('a'), exercise('b')],
        equipmentChosen: true,
      );

  Future<void> open(WidgetTester tester, LibraryState state) async {
    when(() => library.state).thenReturn(state);
    tester.view
      ..physicalSize = const Size(1200, 2600)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LibraryCubit>.value(value: library),
          BlocProvider<EquipmentCubit>.value(value: equipment),
        ],
        child: MaterialApp(
          theme: AppPreset.slate.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ForgeButton(
                label: 'Open',
                onPressed: () => showFilterSheet(context),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  ForgeButton button(WidgetTester tester, String label) =>
      tester.widget<ForgeButton>(find.widgetWithText(ForgeButton, label));

  testWidgets('nothing set: Clear all off, every criterion Any', (
    tester,
  ) async {
    await open(tester, state());

    expect(button(tester, 'Clear all').onPressed, isNull);
    expect(find.text('Any'), findsNWidgets(4));
    expect(
      find.descendant(
        of: find.widgetWithText(ListRow, 'My equipment'),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the bottom button shows the live count and closes the sheet', (
    tester,
  ) async {
    await open(tester, state());

    await tester.tap(find.text('Show 2 exercises'));
    await tester.pumpAndSettle();
    expect(find.byType(FilterSheet), findsNothing);
  });

  testWidgets('no match turns the bottom button off', (tester) async {
    await open(
      tester,
      const LibraryState(filter: LibraryFilter(onlyFavorites: true)),
    );

    expect(button(tester, 'No exercises match').onPressed, isNull);
    await tester.tap(find.text('Clear all'));
    verify(library.clearFilters).called(1);
  });

  testWidgets('a criterion names its values and sets them in a check sheet '
      'over the filters', (tester) async {
    await open(
      tester,
      state(filter: const LibraryFilter(muscles: {Muscle.lat, Muscle.pec})),
    );
    expect(find.text('Chest, Lats'), findsOneWidget);

    await tester.tap(find.text('Muscle'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckRow), findsNWidgets(Muscle.values.length));
    await tester.tap(find.text('Lats'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => library.setMuscles({Muscle.pec})).called(1);
    expect(find.byType(CheckSheet<Muscle>), findsNothing);
    expect(find.byType(FilterSheet), findsOneWidget);
  });

  testWidgets('My equipment stacks its picker and returns after Save', (
    tester,
  ) async {
    await open(tester, state());

    await tester.tap(find.text('My equipment'));
    await tester.pumpAndSettle();
    expect(find.text('Bodyweight exercises are always included.'), findsOne);
    expect(find.text('Bodyweight'), findsNothing);
    await tester.tap(find.text('Bench'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => equipment.save({Equipment.barbell})).called(1);
    expect(find.byType(FilterSheet), findsOneWidget);
  });
}
