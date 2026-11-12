import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/features/notifications/data/notification_payloads.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('the start is the splash, retry, onboarding and its suggestion', () {
    for (final location in [
      '',
      Routes.splash,
      Routes.startFailed,
      Routes.onboarding,
      Routes.onboardingSignIn,
      Routes.afterOnboarding,
    ]) {
      expect(isPastStart(location), isFalse, reason: location);
    }
    for (final location in [
      Routes.today,
      Routes.profile,
      Routes.workout,
      Routes.history,
    ]) {
      expect(isPastStart(location), isTrue, reason: location);
    }
  });

  /// A router shaped like the app's: tabs in a shell, the workout pushed
  /// above them with its picker and exercise details above it.
  Future<GoRouter> pumpRouter(WidgetTester tester) async {
    Widget page(GoRouterState state) => Text(state.uri.path);
    GoRoute route(String path, {List<RouteBase> routes = const []}) =>
        GoRoute(path: path, builder: (_, state) => page(state), routes: routes);
    final router = GoRouter(
      initialLocation: Routes.today,
      routes: [
        route(
          Routes.workout,
          routes: [route('pick'), route('exercises/:exerciseId')],
        ),
        route(Routes.paywall),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => shell,
          branches: [
            StatefulShellBranch(routes: [route(Routes.today)]),
            StatefulShellBranch(
              routes: [
                route(
                  Routes.progress,
                  routes: [
                    route('body', routes: [route('measure')]),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    return router;
  }

  List<String> open(GoRouter router) =>
      openLocations(router.routerDelegate.currentConfiguration);

  testWidgets('open pages include those pushed, the one in front last', (
    tester,
  ) async {
    final router = await pumpRouter(tester);
    expect(open(router).last, Routes.today);

    unawaited(router.push(Routes.workout));
    await tester.pumpAndSettle();
    expect(open(router), [Routes.today, Routes.workout]);
    // What the stack's uri says: the tab under the pushed page.
    expect(router.routerDelegate.currentConfiguration.uri.path, Routes.today);

    unawaited(router.push('${Routes.workout}/pick'));
    await tester.pumpAndSettle();
    expect(open(router).last, '${Routes.workout}/pick');
  });

  group('with the workout open', () {
    for (final above in [
      null,
      '${Routes.workout}/pick',
      Routes.workoutExercise('ex_squat'),
      Routes.paywall,
    ]) {
      testWidgets('${above ?? 'in front'}: taps keep it', (tester) async {
        final router = await pumpRouter(tester);
        unawaited(router.push(Routes.workout));
        await tester.pumpAndSettle();
        if (above != null) {
          unawaited(router.push(above));
          await tester.pumpAndSettle();
        }

        expect(lockScreenDestination(open(router), inProgress: true), isNull);
        expect(
          notificationDestination(NotificationTarget.workout, open(router)),
          isNull,
        );
      });
    }
  });

  testWidgets('without it, a lock-screen tap pushes it, a reminder goes to '
      'Today', (tester) async {
    final router = await pumpRouter(tester);
    router.go('${Routes.progress}/body');
    await tester.pumpAndSettle();

    expect(
      lockScreenDestination(open(router), inProgress: true),
      Routes.workout,
    );
    expect(
      notificationDestination(NotificationTarget.workout, open(router)),
      Routes.today,
    );
    // One left behind with no workout in progress only opens the app.
    expect(lockScreenDestination(open(router), inProgress: false), isNull);
  });

  testWidgets('a measurement reminder opens a new measurement day, unless '
      'one is open', (tester) async {
    final router = await pumpRouter(tester);
    expect(
      notificationDestination(NotificationTarget.measurement, open(router)),
      Routes.bodyMeasureNew,
    );
    router.go(Routes.bodyMeasureNew);
    await tester.pumpAndSettle();
    expect(
      notificationDestination(NotificationTarget.measurement, open(router)),
      isNull,
    );
  });

  test('announcements lead to Today', () {
    expect(
      notificationDestination(NotificationTarget.announcement, [Routes.steps]),
      Routes.today,
    );
  });
}
