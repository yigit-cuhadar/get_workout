import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/app/router.dart';
import 'package:go_router/go_router.dart';
import 'package:get_workout/core/unsaved_changes.dart';

class _Page implements UnsavedPage {
  _Page(this.location, {this.hasUnsavedChanges = true});

  @override
  final String location;

  @override
  bool hasUnsavedChanges;

  @override
  Future<bool> confirmDiscard() async => true;
}

void main() {
  group('drops', () {
    // Every tab under its own first segment.
    final separate = UnsavedChanges();

    test('going elsewhere in the same tab drops the page', () {
      expect(separate.drops(Routes.program('p1'), Routes.programNew), isTrue);
      expect(separate.drops(Routes.programs, Routes.programEdit('p1')), isTrue);
      expect(separate.drops(Routes.today, '/today/x'), isTrue);
    });

    test('going to the page or past it keeps it', () {
      expect(separate.drops(Routes.programNew, Routes.programNew), isFalse);
      expect(
        separate.drops(
          Routes.calendarWorkoutEdit('w1'),
          Routes.calendarWorkout('w1'),
        ),
        isFalse,
      );
    });

    test('a page whose path only starts the same is dropped', () {
      expect(
        separate.drops('${Routes.programNew}x', Routes.programNew),
        isTrue,
      );
    });

    test('another tab keeps its own stack', () {
      expect(separate.drops(Routes.calendar, Routes.programNew), isFalse);
      expect(
        separate.drops(Routes.profileDetails, Routes.bodyMeasureNew),
        isFalse,
      );
      expect(separate.drops('/profiles', Routes.profileDetails), isFalse);
    });

    test('the Programs and Exercises tabs keep their own stacks', () {
      expect(separate.drops(Routes.exerciseList, Routes.programNew), isFalse);
      expect(
        separate.drops(Routes.programs, Routes.exerciseProgramNew),
        isFalse,
      );
      expect(
        separate.drops(Routes.exerciseList, Routes.exerciseProgramNew),
        isTrue,
      );
      expect(
        separate.drops(Routes.catalogue, Routes.customExerciseNew),
        isFalse,
      );
    });
  });

  group('droppedBy', () {
    test('finds the page with changes that a location drops', () {
      final unsaved = UnsavedChanges();
      final builder = _Page(Routes.programNew);
      final measure = _Page(Routes.bodyMeasureNew);
      unsaved
        ..add(builder)
        ..add(measure);

      expect(unsaved.droppedBy(Routes.program('p1')), builder);
      expect(unsaved.droppedBy(Routes.calendarWorkoutNew), measure);
      expect(unsaved.droppedBy(Routes.today), isNull);
      expect(unsaved.droppedBy(Routes.bodyMeasureNew), isNull);
    });

    test('skips pages without changes', () {
      final unsaved = UnsavedChanges();
      final builder = _Page(Routes.programNew, hasUnsavedChanges: false);
      unsaved.add(builder);

      expect(unsaved.droppedBy(Routes.programs), isNull);
      builder.hasUnsavedChanges = true;
      expect(unsaved.droppedBy(Routes.programs), builder);
    });

    test('forgets a removed page', () {
      final unsaved = UnsavedChanges();
      final builder = _Page(Routes.programNew);
      unsaved
        ..add(builder)
        ..remove(builder);

      expect(unsaved.droppedBy(Routes.programs), isNull);
    });
  });

  group('a router guarded by onEnter', () {
    late GoRouter router;
    late ValueNotifier<bool> dirty;
    late int prompts;

    Future<void> pumpApp(WidgetTester tester) async {
      dirty = ValueNotifier(false);
      prompts = 0;
      final unsaved = UnsavedChanges();
      router = GoRouter(
        initialLocation: '/a',
        onEnter: unsaved.onEnter,
        routes: [
          GoRoute(path: '/c', builder: (_, _) => const Text('c')),
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) =>
                RepositoryProvider.value(value: unsaved, child: shell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/a',
                    builder: (_, _) => const Text('a'),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (_, _) =>
                            _EditPage(dirty: dirty, onPrompt: () => prompts++),
                      ),
                    ],
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(path: '/b', builder: (_, _) => const Text('b')),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go('/a/edit');
      await tester.pumpAndSettle();
    }

    String path() => router.routerDelegate.currentConfiguration.uri.path;

    testWidgets('a page without changes is replaced silently', (tester) async {
      await pumpApp(tester);
      router.go('/b');
      await tester.pumpAndSettle();
      router.go('/a');
      await tester.pumpAndSettle();

      expect(prompts, 0);
      expect(path(), '/a');
      expect(find.byType(_EditPage), findsNothing);
    });

    testWidgets('going into another tab keeps a page with changes there', (
      tester,
    ) async {
      await pumpApp(tester);
      dirty.value = true;
      router.go('/b');
      await tester.pumpAndSettle();

      expect(prompts, 0);
      expect(path(), '/b');
    });

    testWidgets('a link that would drop changes brings their tab up and '
        'asks; keeping them stays', (tester) async {
      await pumpApp(tester);
      dirty.value = true;
      router.go('/b');
      await tester.pumpAndSettle();

      router.go('/a');
      await tester.pumpAndSettle();
      expect(prompts, 1);
      expect(path(), '/a/edit');
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      expect(path(), '/a/edit');
      expect(find.byType(_EditPage), findsOneWidget);
    });

    testWidgets('discarding lets the link through, asking once', (
      tester,
    ) async {
      await pumpApp(tester);
      dirty.value = true;
      router.go('/b');
      await tester.pumpAndSettle();

      router.go('/a');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(prompts, 1);
      expect(path(), '/a');
      expect(find.byType(_EditPage), findsNothing);
    });

    testWidgets('refusing many times in a row keeps the page', (tester) async {
      await pumpApp(tester);
      dirty.value = true;

      for (var i = 0; i < 7; i++) {
        router.go('/a');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep'));
        await tester.pumpAndSettle();
      }

      expect(prompts, 7);
      expect(path(), '/a/edit');
      expect(find.byType(_EditPage), findsOneWidget);
    });

    testWidgets('a page under a route above the tabs is brought up first', (
      tester,
    ) async {
      await pumpApp(tester);
      dirty.value = true;
      unawaited(router.push('/c'));
      await tester.pumpAndSettle();

      router.go('/a');
      await tester.pumpAndSettle();
      expect(prompts, 1);
      expect(find.text('c'), findsNothing);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      expect(path(), '/a/edit');
      expect(find.byType(_EditPage), findsOneWidget);
    });

    testWidgets('a link while the back prompt is open asks nothing more', (
      tester,
    ) async {
      await pumpApp(tester);
      dirty.value = true;
      await tester.pump();
      unawaited(tester.binding.handlePopRoute());
      await tester.pumpAndSettle();

      router.go('/a');
      await tester.pumpAndSettle();
      expect(prompts, 1);
      expect(find.text('Discard'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(path(), '/a');
      expect(find.byType(_EditPage), findsNothing);
    });

    testWidgets('a push asks nothing', (tester) async {
      await pumpApp(tester);
      dirty.value = true;
      unawaited(router.push('/c'));
      await tester.pumpAndSettle();

      expect(prompts, 0);
      expect(find.text('c'), findsOneWidget);
    });

    testWidgets('back asks once, through the page alone', (tester) async {
      await pumpApp(tester);
      dirty.value = true;
      await tester.pump();
      // The system back button.
      unawaited(tester.binding.handlePopRoute());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(prompts, 1);
      expect(path(), '/a');
    });

    testWidgets('leaving after a save asks nothing', (tester) async {
      await pumpApp(tester);
      dirty.value = true;
      dirty.value = false;
      router.go('/a');
      await tester.pumpAndSettle();

      expect(prompts, 0);
      expect(path(), '/a');
    });
  });
}

/// Like the app's editing pages: a `PopScope` asking on back, and the same
/// prompt for a navigation that would drop it.
class _EditPage extends StatelessWidget {
  const _EditPage({required this.dirty, required this.onPrompt});

  final ValueNotifier<bool> dirty;
  final VoidCallback onPrompt;

  Future<bool> _confirm(BuildContext context) async {
    onPrompt();
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
    hasChanges: () => dirty.value,
    confirmDiscard: () => _confirm(context),
    child: ValueListenableBuilder(
      valueListenable: dirty,
      builder: (context, dirty, _) => PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await UnsavedChangesGuard.ask(context) && context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: const Text('edit'),
      ),
    ),
  );
}
