import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/programs/presentation/exercise_picker_page.dart';
import 'package:get_workout/features/programs/presentation/program_builder_page.dart';
import 'package:get_workout/features/programs/presentation/programs_page.dart';
import 'package:get_workout/features/subscription/presentation/paywall_page.dart';
import 'package:get_workout/features/workout/presentation/workout_bar.dart';
import 'package:get_workout/features/workout/presentation/workout_page.dart';

import '../features/programs/fixtures.dart';
import 'flow_harness.dart' as flow;
import 'training_world.dart';

/// The real router's routes on iOS and Android: pushed pages, pages over
/// the flow and the back swipe of a page with unsaved changes.
void main() {
  final exercises = [move('squat', name: 'Back Squat')];

  ModalRoute<Object?> routeOf(WidgetTester tester, Type page) =>
      ModalRoute.of(tester.element(find.byType(page)))!;

  /// Whether [page] is drawn by the iOS slide.
  bool slides(Type page) => find
      .ancestor(
        of: find.byType(page),
        matching: find.byType(CupertinoPageTransition),
      )
      .evaluate()
      .isNotEmpty;

  /// A swipe from the left edge across most of the screen.
  Future<void> edgeSwipe(WidgetTester tester) async {
    await tester.dragFrom(const Offset(5, 400), const Offset(300, 0));
    await settle(tester);
  }

  /// A program builder opened from the Programs tab.
  Future<TrainingWorld> openBuilder(WidgetTester tester) async {
    final app = TrainingWorld(exercises: exercises);
    await app.start(tester);
    await openTab(tester, 'Programs');
    await tapText(tester, 'New program');
    expect(find.byType(ProgramBuilderPage), findsOneWidget);
    return app;
  }

  /// A workout with one exercise, opened from Today.
  Future<TrainingWorld> openWorkout(WidgetTester tester) async {
    final app = TrainingWorld(exercises: exercises);
    await app.start(tester);
    await openTab(tester, 'Today');
    await tapText(tester, 'Start empty workout');
    await tapOn(tester, find.widgetWithText(ForgeButton, 'Add exercises'));
    await tapText(tester, 'Back Squat');
    await tapText(tester, 'Add 1 exercise');
    expect(find.byType(WorkoutPage), findsOneWidget);
    return app;
  }

  /// The workout page's header.
  Finder workoutHeader() => find.descendant(
    of: find.byType(WorkoutPage),
    matching: find.byType(ForgeAppBar),
  );

  /// Whether the workout rises from the bottom as a full-screen page.
  void expectRising(WidgetTester tester) {
    // Its grabber above the header.
    expect(
      find.descendant(
        of: find.byType(WorkoutPage),
        matching: find.byType(ForgeGrabber),
      ),
      findsOneWidget,
    );
    final route = routeOf(tester, WorkoutPage);
    expect(route, isA<PageRoute<Object?>>());
    expect((route as PageRoute<Object?>).fullscreenDialog, isTrue);
    expect(route.opaque, isTrue);
    expect(
      find.ancestor(
        of: find.byType(WorkoutPage),
        matching: find.byType(CupertinoFullscreenDialogTransition),
      ),
      findsWidgets,
    );
  }

  /// A drag down on the workout's header closes it to its bar, which opens
  /// it again; a short one springs back.
  Future<void> dragsDownToItsBar(WidgetTester tester) async {
    await tester.timedDrag(
      workoutHeader(),
      const Offset(0, 60),
      const Duration(seconds: 1),
    );
    await settle(tester);
    expect(find.byType(WorkoutPage), findsOneWidget);
    expect(routeOf(tester, WorkoutPage).animation!.value, 1);

    await tester.drag(workoutHeader(), const Offset(0, 500));
    await settle(tester);
    expect(find.byType(WorkoutPage), findsNothing);
    expect(find.byType(RunningWorkoutBar), findsOneWidget);

    await tapOn(tester, find.byType(RunningWorkoutBar));
    expect(find.byType(WorkoutPage), findsOneWidget);
    expect(find.text('Back Squat'), findsWidgets);
  }

  /// Runs [body] with the app on iOS.
  Future<void> onIOS(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('on iOS', () {
    testWidgets(
      'a pushed page slides in and the edge swipe takes it back',
      (tester) => onIOS(() async {
        final app = await openBuilder(tester);

        expect(routeOf(tester, ProgramBuilderPage), isA<PageRoute<Object?>>());
        expect(slides(ProgramBuilderPage), isTrue);
        // A tab's first page has no transition of its own.
        expect(slides(ProgramsPage), isFalse);

        await edgeSwipe(tester);
        expect(find.byType(ProgramBuilderPage), findsNothing);
        expect(find.byType(ProgramsPage), findsOneWidget);

        await app.stop(tester);
      }),
    );

    testWidgets(
      'adding exercises opens a sheet that a drag down closes',
      (tester) => onIOS(() async {
        final app = await openBuilder(tester);

        await tapOn(tester, find.text('Add exercises').last);
        expect(
          routeOf(tester, ExercisePickerPage),
          isA<CupertinoSheetRoute<Object?>>(),
        );
        expect(find.bySemanticsLabel('Close'), findsOneWidget);

        await tester.drag(
          find.descendant(
            of: find.byType(ExercisePickerPage),
            matching: find.byType(ForgeAppBar),
          ),
          const Offset(0, 500),
        );
        await settle(tester);
        expect(find.byType(ExercisePickerPage), findsNothing);
        expect(find.byType(ProgramBuilderPage), findsOneWidget);

        await app.stop(tester);
      }),
    );

    testWidgets(
      'the sheet from inside a tab covers the tab bar; after it the tab '
      'still asks before dropping changes',
      (tester) => onIOS(() async {
        final app = await openBuilder(tester);
        await tester.enterText(
          find.widgetWithText(ForgeTextField, 'Program name'),
          'Push Pull',
        );
        await tester.pump();
        final programsTab = find.descendant(
          of: find.byType(ForgeNavigationBar),
          matching: find.text('Programs'),
        );

        await tapOn(tester, find.text('Add exercises').last);
        final sheet = routeOf(tester, ExercisePickerPage);
        expect(sheet, isA<CupertinoSheetRoute<Object?>>());
        // From the root navigator, over the tab's own.
        final builderNavigator = Navigator.of(
          tester.element(find.byType(ProgramBuilderPage)),
        );
        expect(sheet.navigator, isNot(builderNavigator));
        expect(
          sheet.navigator,
          Navigator.of(builderNavigator.context, rootNavigator: true),
        );
        expect(programsTab.hitTestable(), findsNothing);

        await tapOn(tester, find.bySemanticsLabel('Close'));
        expect(find.byType(ExercisePickerPage), findsNothing);
        expect(find.text('Push Pull'), findsOneWidget);

        await tapOn(tester, programsTab);
        expect(find.text('Discard changes?'), findsOneWidget);
        await tapOn(tester, inDialog('Keep editing'));
        expect(find.byType(ProgramBuilderPage), findsOneWidget);
        expect(find.text('Push Pull'), findsOneWidget);

        await app.stop(tester);
      }),
    );

    testWidgets(
      'the edge swipe of a page with unsaved changes asks first',
      (tester) => onIOS(() async {
        final app = await openBuilder(tester);
        await tester.enterText(
          find.widgetWithText(ForgeTextField, 'Program name'),
          'Push Pull',
        );
        await tester.pump();

        // Keep editing: the page springs back and stays.
        await edgeSwipe(tester);
        expect(find.text('Discard changes?'), findsOneWidget);
        await tapOn(tester, inDialog('Keep editing'));
        expect(find.byType(ProgramBuilderPage), findsOneWidget);
        expect(routeOf(tester, ProgramBuilderPage).animation!.value, 1);
        expect(find.text('Push Pull'), findsOneWidget);

        // Discard: it leaves.
        await edgeSwipe(tester);
        expect(find.text('Discard changes?'), findsOneWidget);
        await tapOn(tester, inDialog('Discard'));
        expect(find.byType(ProgramBuilderPage), findsNothing);
        expect(find.byType(ProgramsPage), findsOneWidget);

        await app.stop(tester);
      }),
    );

    testWidgets(
      'a short edge swipe of such a page springs back unasked',
      (tester) => onIOS(() async {
        final app = await openBuilder(tester);
        await tester.enterText(
          find.widgetWithText(ForgeTextField, 'Program name'),
          'Push Pull',
        );
        await tester.pump();

        await tester.timedDragFrom(
          const Offset(5, 400),
          const Offset(60, 0),
          const Duration(seconds: 1),
        );
        await settle(tester);
        expect(find.text('Discard changes?'), findsNothing);
        expect(routeOf(tester, ProgramBuilderPage).animation!.value, 1);

        await app.stop(tester);
      }),
    );

    testWidgets(
      'the workout rises from the bottom and a drag down puts it back to '
      'its bar',
      (tester) => onIOS(() async {
        final app = await openWorkout(tester);
        expectRising(tester);
        await dragsDownToItsBar(tester);

        // ⌄ does the same.
        await tapOn(tester, find.bySemanticsLabel('Minimize'));
        expect(find.byType(WorkoutPage), findsNothing);
        expect(find.byType(RunningWorkoutBar), findsOneWidget);

        await app.stop(tester);
      }),
    );

    testWidgets(
      'the exercise picker opens over the workout and closes back to it',
      (tester) => onIOS(() async {
        final app = await openWorkout(tester);
        await tapOn(
          tester,
          find.widgetWithText(ForgeAddButton, 'Add exercises'),
        );
        expect(
          routeOf(tester, ExercisePickerPage),
          isA<CupertinoSheetRoute<Object?>>(),
        );
        await tapOn(tester, find.bySemanticsLabel('Close'));
        expect(find.byType(WorkoutPage), findsOneWidget);
        expect(routeOf(tester, WorkoutPage).isCurrent, isTrue);

        await app.stop(tester);
      }),
    );

    group('the paywall', () {
      late flow.FlowApp app;

      setUpAll(flow.registerFlowFallbacks);
      setUp(() => app = flow.FlowApp());
      tearDown(() => app.dispose());

      testWidgets(
        'is a sheet with close',
        (tester) => onIOS(() async {
          await app.startAs(tester, flow.guest);
          await app.entitlement.identify(flow.guest.id);
          await app.tapTab(tester, 'Profile');
          await app.tapText(tester, 'Get Premium');

          expect(
            routeOf(tester, PaywallPage),
            isA<CupertinoSheetRoute<Object?>>(),
          );
          expect(find.bySemanticsLabel('Close'), findsOneWidget);
        }),
      );
    });
  });

  testWidgets('on Android, the workout rises from the bottom too', (
    tester,
  ) async {
    final app = await openWorkout(tester);
    expectRising(tester);
    await dragsDownToItsBar(tester);

    await app.stop(tester);
  });

  testWidgets('on Android, adding exercises opens a full-screen dialog', (
    tester,
  ) async {
    final app = await openBuilder(tester);

    await tapOn(tester, find.text('Add exercises').last);
    final route = routeOf(tester, ExercisePickerPage);
    expect(route, isNot(isA<CupertinoSheetRoute<Object?>>()));
    expect(route, isA<PageRoute<Object?>>());
    expect((route as PageRoute<Object?>).fullscreenDialog, isTrue);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);

    await app.stop(tester);
  });
}
