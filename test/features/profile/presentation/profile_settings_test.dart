import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/featured_card.dart';
import 'package:get_workout/features/notifications/presentation/notifications_cubit.dart';
import 'package:get_workout/features/notifications/presentation/reminder_settings_group.dart';
import 'package:get_workout/features/profile/presentation/profile_page.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/settings/presentation/settings_section.dart';
import 'package:get_workout/features/subscription/presentation/premium_card.dart';
import 'package:get_workout/features/subscription/presentation/premium_trial_cubit.dart';
import 'package:get_workout/features/workout/presentation/rest_timer_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../../component_harness.dart';

class _SettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _NotificationsCubit extends MockCubit<NotificationsState>
    implements NotificationsCubit {}

class _RestTimerCubit extends MockCubit<RestTimerState>
    implements RestTimerCubit {}

class _TrialCubit extends MockCubit<OfferPeriod?>
    implements PremiumTrialCubit {}

class _EntitlementCubit extends MockCubit<EntitlementState>
    implements EntitlementCubit {}

void main() {
  const metric = UserSettings(
    weightUnit: WeightUnit.kg,
    lengthUnit: LengthUnit.cm,
  );
  late _SettingsCubit settings;
  late _NotificationsCubit notifications;
  late _RestTimerCubit rest;

  setUpAll(() => registerFallbackValue(metric));

  setUp(() {
    settings = _SettingsCubit();
    notifications = _NotificationsCubit();
    rest = _RestTimerCubit();
    when(() => settings.update(any())).thenAnswer((_) async {});
    when(notifications.allow).thenAnswer((_) async => false);
    when(notifications.openSettings).thenAnswer((_) async {});
    when(() => rest.setNotify(any())).thenAnswer((_) async => false);
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    UserSettings shown = metric,
    bool? allowed = true,
    bool? asked = true,
  }) {
    when(() => settings.state).thenReturn(SettingsState(shown, loaded: true));
    when(() => notifications.state)
        .thenReturn(NotificationsState(allowed: allowed, asked: asked));
    return pumpComponent(
      tester,
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<NotificationsCubit>.value(value: notifications),
          BlocProvider<RestTimerCubit>.value(value: rest),
        ],
        child: SingleChildScrollView(child: child),
      ),
    );
  }

  group('Workout settings', () {
    testWidgets('show the rest rows only while the rest timer is on', (
      tester,
    ) async {
      await pump(tester, const WorkoutSettingsGroups());
      expect(find.text('Default rest'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      expect(find.text('Notify when rest is over'), findsOneWidget);
      expect(find.text('Chime · vibrate (default)'), findsOneWidget);

      await pump(
        tester,
        const WorkoutSettingsGroups(),
        shown: metric.copyWith(
          restTimer: const RestTimerSettings(enabled: false),
        ),
      );
      expect(find.text('Rest timer'), findsOneWidget);
      expect(find.text('Default rest'), findsNothing);
      expect(find.text('Notify when rest is over'), findsNothing);
      expect(find.text('Rest sound and vibration'), findsNothing);
    });

    testWidgets('summarise the bar and plates', (tester) async {
      await pump(tester, const WorkoutSettingsGroups());
      expect(
        find.text('20 kg bar · 25, 20, 15, 10, 5, 2.5, 1.25'),
        findsOneWidget,
      );
    });

    testWidgets('the effort question offers Off, its default marked', (
      tester,
    ) async {
      await pump(tester, const WorkoutSettingsGroups());
      expect(find.text('By feel (default)'), findsOneWidget);
      await tester.tap(find.text('Effort question'));
      await tester.pumpAndSettle();
      expect(find.text('Asked after each set you log.'), findsOneWidget);
      expect(find.text('0, 1, 2, 3 or 4+ reps left'), findsOneWidget);
      // Off first, then the scales.
      final labels = tester
          .widget<ChoiceGrid>(find.byType(ChoiceGrid))
          .options
          .map((option) => option.label);
      expect(labels, [
        'Off',
        'By feel (default)',
        'RIR · reps in reserve',
        'RPE · rated effort',
      ]);
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();

      final saved =
          verify(() => settings.update(captureAny())).captured.single
              as UserSettings;
      expect(saved.askEffort, isFalse);
      expect(saved.effortScale, EffortScale.byFeel);
    });

    testWidgets('a scale picked turns the effort question back on', (
      tester,
    ) async {
      await pump(
        tester,
        const WorkoutSettingsGroups(),
        shown: metric.copyWith(askEffort: false),
      );
      expect(find.text('Off'), findsOneWidget);
      await tester.tap(find.text('Effort question'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RIR · reps in reserve'));
      await tester.pumpAndSettle();

      final saved =
          verify(() => settings.update(captureAny())).captured.single
              as UserSettings;
      expect(saved.askEffort, isTrue);
      expect(saved.effortScale, EffortScale.rir);
    });

    testWidgets('the rest sound is picked in a choice sheet', (tester) async {
      await pump(tester, const WorkoutSettingsGroups());
      await tester.tap(find.text('Rest sound and vibration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vibrate'));
      await tester.pumpAndSettle();

      final saved =
          verify(() => settings.update(captureAny())).captured.single
              as UserSettings;
      expect(saved.restTimer.alert, RestAlert.vibrate);
    });

    testWidgets('keep screen on is a switch saved at once', (tester) async {
      await pump(tester, const WorkoutSettingsGroups());
      final keep = find.ancestor(
        of: find.text('Keep screen on'),
        matching: find.byType(ListRow),
      );
      await tester.tap(
        find.descendant(of: keep, matching: find.byType(ForgeSwitch)),
      );
      await tester.pumpAndSettle();

      final saved =
          verify(() => settings.update(captureAny())).captured.single
              as UserSettings;
      expect(saved.keepScreenOn, isFalse);
    });

    testWidgets('notify when rest is over asks first without permission, and '
        '"Not now" changes nothing', (tester) async {
      await pump(tester, const WorkoutSettingsGroups(), allowed: false);
      final notify = find.ancestor(
        of: find.text('Notify when rest is over'),
        matching: find.byType(ListRow),
      );
      await tester.tap(
        find.descendant(of: notify, matching: find.byType(ForgeSwitch)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Allow notifications?'), findsOneWidget);
      expect(
        find.text(
          'Rest alerts are notifications, so GetWorkout needs your '
          'permission to send them.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      verifyNever(notifications.allow);
      verifyNever(() => rest.setNotify(any()));
    });

    testWidgets('a refusal stores the wish and points to the settings', (
      tester,
    ) async {
      await pump(tester, const WorkoutSettingsGroups(), allowed: false);
      final notify = find.ancestor(
        of: find.text('Notify when rest is over'),
        matching: find.byType(ListRow),
      );
      await tester.tap(
        find.descendant(of: notify, matching: find.byType(ForgeSwitch)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      verify(() => rest.setNotify(true)).called(1);
      expect(find.text('Notifications are off'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      verify(notifications.openSettings).called(1);
    });
  });

  group('Reminders', () {
    testWidgets('the notice shows whenever the device refuses', (tester) async {
      await pump(tester, const ReminderSettingsGroup(), allowed: false);
      expect(find.byType(NoticeBanner), findsOneWidget);
      expect(find.text('Notifications are off'), findsOneWidget);

      await pump(tester, const ReminderSettingsGroup());
      expect(find.byType(NoticeBanner), findsNothing);
    });

    testWidgets('the notice asks on a device never asked, else opens the '
        'settings', (tester) async {
      await pump(
        tester,
        const ReminderSettingsGroup(),
        allowed: false,
        asked: false,
      );
      expect(find.text('Open settings'), findsNothing);
      await tester.tap(find.text('Allow notifications'));
      verify(notifications.allow).called(1);

      await pump(tester, const ReminderSettingsGroup(), allowed: false);
      expect(find.text('Allow notifications'), findsNothing);
      await tester.tap(find.text('Open settings'));
      verify(notifications.openSettings).called(1);
    });

    testWidgets('a reminder that is off hides its rows', (tester) async {
      await pump(tester, const ReminderSettingsGroup());
      expect(find.text('On training days'), findsOneWidget);
      expect(find.text('Time'), findsNothing);
      expect(find.text('Repeat'), findsNothing);

      await pump(
        tester,
        const ReminderSettingsGroup(),
        shown: metric.copyWith(
          workoutReminder: const WorkoutReminderSettings(enabled: true),
          measurementReminder: const MeasurementReminderSettings(enabled: true),
        ),
      );
      expect(find.text('Time'), findsNWidgets(2));
      expect(find.text('Repeat'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
    });
  });

  group('Premium card', () {
    Future<void> pumpCard(
      WidgetTester tester,
      EntitlementState state, {
      OfferPeriod? trial,
    }) {
      final entitlement = _EntitlementCubit();
      when(() => entitlement.state).thenReturn(state);
      final trials = _TrialCubit();
      when(() => trials.state).thenReturn(trial);
      return pumpComponent(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<EntitlementCubit>.value(value: entitlement),
            BlocProvider<PremiumTrialCubit>.value(value: trials),
          ],
          child: const PremiumCard(),
        ),
      );
    }

    FeaturedCard card(WidgetTester tester) =>
        tester.widget(find.byType(FeaturedCard));

    testWidgets('a free user sees Premium, its trial, its benefits and Get '
        'Premium', (tester) async {
      await pumpCard(
        tester,
        const EntitlementInactive(),
        trial: const OfferPeriod(7, PeriodUnit.day),
      );
      expect(find.byType(FeaturedCard), findsNothing);
      expect(find.byType(PlanCard), findsOneWidget);
      expect(find.text('GetWorkout Premium'), findsOneWidget);
      expect(find.widgetWithText(ForgeTag, '7 days free'), findsOneWidget);
      expect(tester.widget<BenefitList>(find.byType(BenefitList)).lines, [
        'Program generator',
        '23 more ready-made programs',
        'Charts beyond 2 weeks',
      ]);
      expect(find.widgetWithText(ForgeButton, 'Get Premium'), findsOneWidget);
    });

    testWidgets('a free user with no trial known sees no tag', (tester) async {
      await pumpCard(tester, const EntitlementInactive());
      expect(find.byType(ForgeTag), findsNothing);
      expect(find.text('Get Premium'), findsOneWidget);
    });

    testWidgets('the status is muted and offers nothing while unknown', (
      tester,
    ) async {
      await pumpCard(tester, const EntitlementUnknown());
      expect(card(tester).title, 'Checking…');
      expect(card(tester).titleTone, FeaturedTitleTone.muted);
      expect(find.byType(ForgeButton), findsNothing);
    });

    testWidgets('a payment problem is danger, with Manage subscription', (
      tester,
    ) async {
      await pumpCard(
        tester,
        const EntitlementActive(
          Entitlement(isActive: true, hasBillingIssue: true),
        ),
      );
      expect(card(tester).titleTone, FeaturedTitleTone.danger);
      expect(card(tester).action, isNull);
      expect(card(tester).moreActions.single.label, 'Manage subscription');
    });

    testWidgets('a renewal this year names the day without the year', (
      tester,
    ) async {
      final date = DateTime(DateTime.now().year, 12, 13);
      await pumpCard(
        tester,
        EntitlementActive(
          Entitlement(isActive: true, expiresAt: date, willRenew: true),
        ),
      );
      expect(card(tester).title, 'Premium, renews Dec 13');
    });

    testWidgets('lifetime Premium has nothing to manage', (tester) async {
      await pumpCard(
        tester,
        const EntitlementActive(Entitlement(isActive: true)),
      );
      expect(card(tester).title, 'Premium');
      expect(find.byType(ForgeButton), findsNothing);
    });
  });

  test('initials come from a name, or the first letter of an email', () {
    expect(initialsOf('Sam Morgan'), 'SM');
    expect(initialsOf('sam'), 'S');
    expect(initialsOf('sam@example.com'), 'S');
    expect(initialsOf('Ana María López'), 'AM');
  });

  test('an Apple relay address is told apart from a real one', () {
    expect(isAppleRelay('x7k2@privaterelay.appleid.com'), isTrue);
    expect(isAppleRelay('X7K2@PrivateRelay.AppleID.com'), isTrue);
    expect(isAppleRelay('sam@icloud.com'), isFalse);
    expect(isAppleRelay(null), isFalse);
  });
}
