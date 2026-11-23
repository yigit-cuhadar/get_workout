import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/presentation/catalogue_page.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/steps/domain/steps.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:mocktail/mocktail.dart';

import '../features/programs/fixtures.dart' show card;
import 'flow_harness.dart';

class _FakeActiveProgram extends Fake implements ActiveProgram {}

/// The splash's slow-start line, which forge_ui does not export.
final slowLine = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == 'RunnerLine',
);

/// Every choice question answered, so Continue goes through them.
const choicesAnswered = UserProfile(
  goal: Goal.buildMuscle,
  level: Level.beginner,
  daysPerWeek: 3,
  equipment: {Equipment.dumbbell, Equipment.bench},
  sex: Sex.male,
);

/// The question on screen, from 1.
int question(WidgetTester tester) =>
    tester.widget<StepProgress>(find.byType(StepProgress)).current;

void main() {
  late FlowApp app;

  setUpAll(() {
    registerFlowFallbacks();
    registerFallbackValue(_FakeActiveProgram());
  });

  setUp(() {
    app = FlowApp()
      ..storedProfile = const UserProfile()
      // The catalogue's user owns no equipment.
      ..readyMade = [
        card(
          'pr_free',
          equipment: const [Equipment.bodyweight],
          profile: EquipmentProfile.bodyweight,
        ),
      ]
      ..healthAccess = StepsAccess.explain
      ..notificationsAllowed = false;
  });

  tearDown(() => app.dispose());

  Future<void> tapText(WidgetTester tester, String text) =>
      app.tapText(tester, text);

  Future<void> next(WidgetTester tester) => tapText(tester, 'Continue');

  testWidgets('the splash shows its slow line after 2 s; a failed start '
      'retries onto the welcome', (tester) async {
    app.start();
    var attempts = 0;
    when(() => app.repository.signInAnonymously()).thenAnswer((_) async {
      if (++attempts == 1) return const Err(NetworkFailure());
      app.users.add(guest);
      return const Ok(guest);
    });
    await app.pump(tester);
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('GetWorkout'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(slowLine, findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(slowLine, findsOneWidget);

    // No session, and the guest could not start.
    app.users.add(null);
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't start. Check your connection and try again."),
      findsOneWidget,
    );
    expect(slowLine, findsNothing);

    await tapText(tester, 'Retry');

    expect(attempts, 2);
    expect(find.text('Train with a plan that fits your week.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('a new user answers the nine questions, going back once, turns '
      'on reminders, skips health and starts the suggested program', (
    tester,
  ) async {
    await app.startAs(tester, guest);
    when(() => app.notifications.allow()).thenAnswer((_) async => true);
    expect(find.text('I already have an account'), findsOneWidget);

    await tapText(tester, 'Get started');
    expect(question(tester), 1);
    await tapText(tester, 'Build muscle');
    await next(tester);
    expect(question(tester), 2);
    await tapText(tester, 'Beginner');
    await next(tester);
    await tapText(tester, '3 days');
    await next(tester);
    await tapText(tester, 'Dumbbells and a bench');
    await next(tester);
    expect(question(tester), 5);
    await tapText(tester, 'Female');

    // Back keeps the answers on both sides.
    await app.tapBack(tester);
    expect(question(tester), 4);
    await next(tester);
    expect(question(tester), 5);
    await next(tester);
    // The number questions start answered.
    for (final step in [6, 7, 8, 9]) {
      expect(question(tester), step);
      await next(tester);
    }

    expect(find.text('Remind you on training days?'), findsOneWidget);
    await tapText(tester, 'Turn on reminders');
    verify(() => app.notifications.allow()).called(1);

    expect(find.text('Bring in steps and cardio?'), findsOneWidget);
    await tapText(tester, 'Skip');
    verifyNever(app.health.allow);

    expect(find.text('Your plan is ready'), findsOneWidget);
    expect(find.text('Program pr_free'), findsOneWidget);
    final saved =
        verify(() => app.profiles.completeOnboarding('u1', captureAny()))
                .captured
                .single
            as UserProfile;
    expect(saved.goal, Goal.buildMuscle);
    expect(saved.level, Level.beginner);
    expect(saved.daysPerWeek, 3);
    expect(saved.sex, Sex.female);

    await tapText(tester, 'Start this program');

    final copy =
        verify(() => app.programs.createProgram('u1', captureAny()))
                .captured
                .single
            as Program;
    expect(copy.name, 'Program pr_free');
    verifyNever(() => app.programs.startProgram(any(), any()));
    expect(app.path(), Routes.program('p1'));
    expect(find.byType(ForgeNavigationBar), findsOneWidget);
  });

  testWidgets('with notifications allowed already the reminder step is not '
      'asked; with health granted neither is that one', (tester) async {
    app
      ..storedProfile = choicesAnswered
      ..notificationsAllowed = true
      ..healthAccess = StepsAccess.granted;
    await app.startAs(tester, guest);
    await tapText(tester, 'Get started');
    for (var i = 0; i < ProfileField.values.length; i++) {
      await next(tester);
    }

    expect(find.text('Remind you on training days?'), findsNothing);
    expect(find.text('Bring in steps and cardio?'), findsNothing);
    expect(find.text('Your plan is ready'), findsOneWidget);
    verifyNever(() => app.notifications.allow());
  });

  testWidgets('with notifications allowed already it goes on to health', (
    tester,
  ) async {
    app
      ..storedProfile = choicesAnswered
      ..notificationsAllowed = true;
    await app.startAs(tester, guest);
    await tapText(tester, 'Get started');
    for (var i = 0; i < ProfileField.values.length; i++) {
      await next(tester);
    }

    expect(find.text('Remind you on training days?'), findsNothing);
    expect(find.text('Bring in steps and cardio?'), findsOneWidget);
  });

  testWidgets('Not now skips the reminders; Connect asks for health access; '
      'See other programs opens the catalogue', (tester) async {
    app.storedProfile = choicesAnswered;
    await app.startAs(tester, guest);
    await tapText(tester, 'Get started');
    for (var i = 0; i < ProfileField.values.length; i++) {
      await next(tester);
    }

    await tapText(tester, 'Not now');
    verifyNever(() => app.notifications.allow());

    expect(find.text('Bring in steps and cardio?'), findsOneWidget);
    await tester.tap(find.textContaining('Connect '));
    await tester.pumpAndSettle();
    verify(app.health.allow).called(1);

    expect(find.text('Your plan is ready'), findsOneWidget);
    await tapText(tester, 'See other programs');

    expect(find.byType(CataloguePage), findsOneWidget);
    expect(app.path(), Routes.catalogue);
    verifyNever(() => app.programs.createProgram(any(), any()));
  });

  testWidgets('while the health prompt is on its way Connect spins and a '
      'second tap asks nothing more', (tester) async {
    app.storedProfile = choicesAnswered;
    await app.startAs(tester, guest);
    await tapText(tester, 'Get started');
    for (var i = 0; i < ProfileField.values.length; i++) {
      await next(tester);
    }
    await tapText(tester, 'Not now');
    // The health step's cubit exists once the step shows.
    final prompt = Completer<void>();
    when(app.health.allow).thenAnswer((_) => prompt.future);

    final connect = find.ancestor(
      of: find.textContaining('Connect '),
      matching: find.byType(ForgeButton),
    );
    await tester.tap(connect);
    await tester.pump();
    expect(tester.widget<ForgeButton>(connect).loading, isTrue);
    await tester.tap(connect);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    verify(app.health.allow).called(1);
    expect(find.text('Bring in steps and cardio?'), findsOneWidget);

    prompt.complete();
    await tester.pumpAndSettle();
    expect(find.text('Your plan is ready'), findsOneWidget);
  });
}
