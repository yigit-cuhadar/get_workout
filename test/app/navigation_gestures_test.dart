import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/programs/presentation/exercise_picker_page.dart';
import 'package:get_workout/features/programs/presentation/program_builder_page.dart';
import 'package:get_workout/features/programs/presentation/programs_page.dart';
import 'package:get_workout/features/subscription/presentation/paywall_page.dart';

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
