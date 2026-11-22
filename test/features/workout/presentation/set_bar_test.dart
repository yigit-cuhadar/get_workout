import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/calculators/domain/calculation.dart';
import 'package:get_workout/features/calculators/domain/calculators_usecases.dart';
import 'package:get_workout/features/calculators/domain/plates.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/workout/domain/effort.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/features/workout/presentation/set_bar.dart';
import 'package:get_workout/features/workout/presentation/workout_editor.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../../exercises/fixtures.dart' as catalogue;
import '../fixtures.dart';

class _MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class _MockEditor extends Mock implements WorkoutEditor<EditedWorkout> {}

Calculation<PlateLoad> _loadPlates(
  double targetKg, {
  required double barKg,
  required List<Plate> plates,
}) => const LoadPlates()(targetKg: targetKg, barKg: barKg, plates: plates);

void main() {
  setUpAll(() => registerFallbackValue((exercise: 0, set: 0)));

  late _MockEditor editor;

  Future<void> pump(
    WidgetTester tester, {
    required WorkoutSet set,
    LoggingType type = LoggingType.weightReps,
    WeightUnit unit = WeightUnit.kg,
    bool plates = true,
    List<Equipment> equipment = const [Equipment.barbell],
    bool known = true,
    bool refused = false,
  }) {
    editor = _MockEditor();
    when(() => editor.toggledSet(any())).thenReturn(null);
    final settings = _MockSettingsCubit();
    when(() => settings.state).thenReturn(
      SettingsState(
        UserSettings(weightUnit: unit, lengthUnit: LengthUnit.cm),
        loaded: true,
      ),
    );
    final exercises = _MockCatalogueCubit();
    when(() => exercises.state).thenReturn(
      CatalogueReady([
        if (known) catalogue.exercise('Bench Press', equipment: equipment),
      ]),
    );
    return tester.pumpWidget(
      MaterialApp(
        theme: AppPreset.shipped.lightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsCubit>.value(value: settings),
              BlocProvider<ExerciseCatalogueCubit>.value(value: exercises),
            ],
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SetBar(
                state: ActiveWorkoutState(
                  status: WorkoutStatus.active,
                  workout: workout('w', [
                    exercise('Bench Press', [set], type: type),
                  ]),
                  picked: (exercise: 0, set: 0),
                  invalidSet: refused ? (exercise: 0, set: 0) : null,
                ),
                editor: editor,
                loadPlates: plates ? _loadPlates : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder platesButton() => find.bySemanticsLabel('Plates');

  /// Opens the breakdown and reads it. The test font's wide glyphs overflow
  /// ForgeInfoCard's fixed 240px rows, which real fonts fit; only that is
  /// let pass.
  Future<ForgeInfoCard> openPlates(WidgetTester tester) async {
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.toString().contains('overflowed')) onError?.call(details);
    };
    await tester.tap(platesButton());
    await tester.pumpAndSettle();
    FlutterError.onError = onError;
    return tester.widget<ForgeInfoCard>(find.byType(ForgeInfoCard));
  }

  testWidgets('the plate button shows the weight on the bar and plates', (
    tester,
  ) async {
    await pump(tester, set: lift(82.5, 8, done: false));

    final card = await openPlates(tester);
    expect(card.title, '82.5 kg');
    expect(card.facts, [('Bar', '20 kg'), ('Each side', '25 + 5 + 1.25 kg')]);
  });

  testWidgets('a weight the plates cannot make adds the closest load', (
    tester,
  ) async {
    await pump(tester, set: lift(63.7, 8, done: false));

    expect((await openPlates(tester)).facts, [
      ('Bar', '20 kg'),
      ('Each side', '20 + 1.25 kg'),
      ('Closest', '62.5 kg'),
    ]);
  });

  testWidgets('the bar alone takes no plates', (tester) async {
    await pump(tester, set: lift(20, 8, done: false));

    expect((await openPlates(tester)).facts, [
      ('Bar', '20 kg'),
      ('Each side', 'No plates'),
    ]);
  });

  testWidgets('a weight below the bar says so', (tester) async {
    await pump(tester, set: lift(15, 8, done: false));

    final card = await openPlates(tester);
    expect(card.facts, [('Bar', '20 kg')]);
    expect(card.note, 'Lighter than the 20 kg bar.');
  });

  testWidgets('pound plates are listed in pounds', (tester) async {
    await pump(
      tester,
      set: lift(WeightUnit.lb.toKg(225), 5, done: false),
      unit: WeightUnit.lb,
    );

    final card = await openPlates(tester);
    expect(card.title, '225 lb');
    expect(card.facts, [('Bar', '45 lb'), ('Each side', '45 + 45 lb')]);
  });

  testWidgets('no plate button without a weight on a bar to break down', (
    tester,
  ) async {
    await pump(tester, set: lift(82.5, 8, done: false), plates: false);
    expect(platesButton(), findsNothing);

    await pump(
      tester,
      set: lift(10, 6, done: false),
      type: LoggingType.weightedBodyweight,
    );
    expect(platesButton(), findsNothing);

    await pump(tester, set: const WorkoutSet(type: SetType.normal, reps: 8));
    expect(platesButton(), findsNothing);

    await pump(
      tester,
      set: lift(32, 40, done: false),
      type: LoggingType.weightDuration,
    );
    expect(platesButton(), findsOneWidget);
  });

  testWidgets('only an exercise on a plate-loaded bar has the button', (
    tester,
  ) async {
    for (final equipment in const [
      [Equipment.dumbbell, Equipment.bench],
      [Equipment.smithMachine],
    ]) {
      await pump(tester, set: lift(32, 8, done: false), equipment: equipment);
      expect(platesButton(), findsNothing);
    }
  });

  for (final (equipment, weight, bar) in const [
    ([Equipment.ezBar], 30.0, '10 kg'),
    ([Equipment.trapBar], 85.0, '25 kg'),
    ([Equipment.ezBar, Equipment.barbell], 60.0, '20 kg'),
  ]) {
    testWidgets('$equipment breaks down on a $bar bar', (tester) async {
      await pump(
        tester,
        set: lift(weight, 5, done: false),
        equipment: equipment,
      );
      expect((await openPlates(tester)).facts.first, ('Bar', bar));
    });
  }

  testWidgets('an exercise the catalogue does not know has no plate button', (
    tester,
  ) async {
    await pump(tester, set: lift(82.5, 8, done: false), known: false);
    expect(platesButton(), findsNothing);
  });

  testWidgets('a refused tick rings the empty field and says why once', (
    tester,
  ) async {
    await pump(
      tester,
      set: const WorkoutSet(type: SetType.normal, reps: 8),
      refused: true,
    );

    expect(
      find.widgetWithText(StepperFieldError, "Enter the set's values first."),
      findsOneWidget,
    );
    final fields = tester.widgetList<StepperField>(find.byType(StepperField));
    expect(fields.map((field) => field.invalid), [true, false]);
  });

  testWidgets("a done set's effort: rows with their meaning, no Skip", (
    tester,
  ) async {
    const set = WorkoutSet(
      type: SetType.normal,
      weightKg: 82.5,
      reps: 8,
      done: true,
      rir: 1,
    );
    await pump(tester, set: set);

    final grid = tester.widget<ChoiceGrid>(find.byType(ChoiceGrid));
    // The same rows as the effort question.
    expect(grid.form, ChoiceListForm.inline);
    expect(grid.options.map((option) => option.label), [
      'Easy',
      'Moderate',
      'Hard',
      'Max',
      'Failed',
    ]);
    expect(grid.options.first.hint, '4+ reps left');
    expect(grid.options.last.hint, 'last rep missed');
    expect(grid.selected, 2);
    expect(find.text('Skip'), findsNothing);
    final settings = BlocProvider.of<SettingsCubit>(
      tester.element(find.byType(SetBar)),
    );
    when(() => settings.tipSeen(Tip.effort)).thenAnswer((_) async {});
    await tester.tap(find.text('Max'));
    verify(
      () =>
          editor.setEffort((exercise: 0, set: 0), const EffortStep.reserve(0)),
    ).called(1);
    // The chosen step again clears it.
    await tester.tap(find.text('Hard'));
    verify(() => editor.setEffort((exercise: 0, set: 0), null)).called(1);
  });

  group('SetBarLayout', () {
    const panel = Key('panel');

    Future<double> panelHeight(WidgetTester tester, bool fullHeight) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppPreset.slate.lightTheme(),
          // The test screen is 600 tall.
          home: SetBarLayout(
            fullHeight: fullHeight,
            content: const SizedBox.expand(),
            panel: const SingleChildScrollView(
              child: SizedBox(key: panel, height: 500),
            ),
          ),
        ),
      );
      return tester
          .getSize(
            find.ancestor(
              of: find.byKey(panel),
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .height;
    }

    testWidgets('the panel takes at most its share of the page', (
      tester,
    ) async {
      expect(
        await panelHeight(tester, false),
        600 * SetBarLayout.maxBottomShare,
      );
    });

    testWidgets('a full-height panel takes its own height', (tester) async {
      expect(await panelHeight(tester, true), 500);
    });
  });
}
