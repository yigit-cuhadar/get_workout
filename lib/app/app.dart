import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_app_gate/forge_app_gate.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:forge_purchases/forge_purchases.dart';

import '../features/devices/presentation/device_session.dart';
import '../features/body/body_module.dart';
import '../features/account/presentation/consent_cubit.dart';
import '../features/account/presentation/delete_account_cubit.dart';
import '../features/analytics/domain/analytics.dart';
import '../features/analytics/presentation/analytics_session.dart';
import '../features/exercises/presentation/body_model_cubit.dart';
import '../features/exercises/presentation/equipment_cubit.dart';
import '../features/exercises/presentation/exercise_catalogue_cubit.dart';
import '../features/profile/presentation/profile_cubit.dart';
import '../features/programs/presentation/program_list_cubit.dart';
import '../features/exercises/presentation/favorites_cubit.dart';
import '../features/notifications/data/notification_payloads.dart';
import '../features/notifications/presentation/notifications_cubit.dart';
import '../features/settings/domain/user_settings.dart';
import '../features/settings/presentation/first_weekday.dart';
import '../features/settings/presentation/settings_cubit.dart';
import '../features/workout/domain/rest_usecases.dart';
import '../features/workout/domain/workout_usecases.dart';
import '../features/workout/presentation/active_workout_cubit.dart';
import '../features/workout/presentation/keep_screen_on.dart';
import '../features/workout/presentation/rest_timer_cubit.dart';
import '../features/subscription/presentation/hard_paywall_gate.dart';
import '../features/subscription/presentation/purchaser_session.dart';
import '../features/subscription/subscription_module.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';
import 'theme.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final _router = buildRouter(
    sl<AuthCubit>(),
    sl<ProfileCubit>(),
    deletionUnderway: sl<DeletionUnderway>(),
    profileDevTools: [if (kDebugMode) ?SubscriptionModule.debugControls(sl)],
  );
  late final AppLifecycleListener _lifecycle;
  late final HardPaywallGate _hardPaywall;
  late final StreamSubscription<AppGateState> _appGate;
  late final StreamSubscription<String?> _taps;
  late final StreamSubscription<void> _lockScreenTaps;
  late final StreamSubscription<bool> _selfEnded;
  late final Analytics _analytics;

  /// The page in front when a screen view was last logged.
  LocalKey? _screenShown;

  /// A tapped notification or lock-screen activity, until the app is past
  /// its start: where it leads with the open pages ([openLocations]; null:
  /// stay), and whether it is pushed onto them rather than gone to.
  ({String? Function(List<String> open) to, bool push})? _tapped;

  @override
  void initState() {
    super.initState();
    // Created now so the store follows the user from the first auth event.
    final purchaser = sl<PurchaserSession>();
    _analytics = sl<Analytics>();
    // Created now so the user properties follow from the first auth event.
    sl<AnalyticsSession>();
    // Created now so the device is recorded from the first auth event.
    sl<DeviceSession>();
    _router.routerDelegate.addListener(_logScreen);
    final rest = sl<RestTimerCubit>();
    BodyModule.startPhotoBackup(sl);
    // Created now so reminders follow the user from the first auth event.
    final notifications = sl<NotificationsCubit>();
    final appGate = sl<AppGateCubit>();
    final deletionUnderway = sl<DeletionUnderway>();
    _hardPaywall = HardPaywallGate(
      router: _router,
      entitlement: sl(),
      offeringHard: sl(),
      // Never over the gate's update or maintenance page, nor during an
      // account deletion.
      blocked: () =>
          deletionUnderway.value ||
          switch (appGate.state.status) {
            UpdateRequired() || Maintenance() => true,
            AppOpen() || UpdateRecommended() => false,
          },
    );
    _appGate = appGate.stream.listen((_) => _hardPaywall.check());
    _router.routerDelegate.addListener(_openTapped);
    _taps = sl<NotificationTaps>().stream.listen((payload) {
      if (payload == NotificationPayloads.activeWorkout) {
        unawaited(_analytics.notificationOpen(NotificationKind.activeWorkout));
        unawaited(_openLockScreenTap());
      } else if (NotificationPayloads.targetOf(payload) case final target?) {
        unawaited(
          _analytics.notificationOpen(switch (target) {
            NotificationTarget.workout => NotificationKind.workout,
            NotificationTarget.measurement => NotificationKind.measurement,
            NotificationTarget.announcement => NotificationKind.announcement,
          }),
        );
        _openNotification(target);
      }
    });
    _lockScreenTaps = sl<WatchLockScreenTaps>()().listen((_) {
      unawaited(_analytics.notificationOpen(NotificationKind.activeWorkout));
      unawaited(_openLockScreenTap());
    });
    final workout = sl<ActiveWorkoutCubit>();
    // A workout that ended itself opens its summary, once the app is past
    // its start.
    _selfEnded = workout.stream
        .map((state) => state.selfEnded)
        .distinct()
        .where((ended) => ended)
        .listen((_) {
          _tapped = (to: selfEndedDestination, push: true);
          _openTapped();
        });
    _lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(sl<ExerciseCatalogueCubit>().appResumed());
        purchaser.resume();
        BodyModule.resumed(sl);
        unawaited(notifications.resumed());
      },
      onHide: rest.hidden,
      onShow: () {
        _hardPaywall.appOpened();
        rest.shown();
        workout.appShown();
      },
    );
  }

  /// A `screen_view` whenever another page comes in front, a tab switch
  /// included.
  void _logScreen() {
    final screen = screenInFront(_router.routerDelegate.currentConfiguration);
    if (screen == null || screen.page == _screenShown) return;
    _screenShown = screen.page;
    unawaited(_analytics.screen(screen.name));
  }

  void _openNotification(NotificationTarget target) {
    _tapped = (
      to: (open) => notificationDestination(target, open),
      push: false,
    );
    _openTapped();
  }

  /// A tap on the workout's lock-screen activity (iOS) or notification
  /// (Android). Waits for the workout to be loaded, so a tap that launched
  /// the app opens the workout in progress too.
  Future<void> _openLockScreenTap() async {
    final workout = sl<ActiveWorkoutCubit>();
    if (workout.state.status == WorkoutStatus.loading) {
      await workout.stream.firstWhere(
        (state) => state.status != WorkoutStatus.loading,
      );
    }
    if (!mounted) return;
    _tapped = (
      to: (open) =>
          lockScreenDestination(open, inProgress: workout.state.inProgress),
      push: true,
    );
    _openTapped();
  }

  void _openTapped() {
    final tapped = _tapped;
    final open = openLocations(_router.routerDelegate.currentConfiguration);
    if (tapped == null || open.isEmpty || !isPastStart(open.last)) return;
    _tapped = null;
    final destination = tapped.to(open);
    if (destination == null) return;
    // Never from inside the router delegate's own notification.
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        if (tapped.push) {
          unawaited(_router.push(destination));
        } else {
          _router.go(destination);
        }
      })
      ..ensureVisualUpdate();
  }

  @override
  void dispose() {
    unawaited(_taps.cancel());
    unawaited(_lockScreenTaps.cancel());
    unawaited(_selfEnded.cancel());
    unawaited(_appGate.cancel());
    unawaited(_hardPaywall.cancel());
    _router.routerDelegate
      ..removeListener(_openTapped)
      ..removeListener(_logScreen);
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        RepositoryProvider.value(value: _analytics),
        BlocProvider.value(value: sl<AppGateCubit>()),
        BlocProvider.value(value: sl<AuthCubit>()),
        BlocProvider.value(value: sl<SettingsCubit>()),
        // Created at start, so consent is applied whatever the tab.
        BlocProvider.value(value: sl<ConsentCubit>()),
        BlocProvider.value(value: sl<ProfileCubit>()),
        BlocProvider.value(value: sl<ExerciseCatalogueCubit>()),
        BlocProvider.value(value: sl<FavoritesCubit>()),
        BlocProvider.value(value: sl<EquipmentCubit>()),
        BlocProvider.value(value: sl<BodyModelCubit>()),
        BlocProvider.value(value: sl<ActiveWorkoutCubit>()),
        BlocProvider.value(value: sl<RestTimerCubit>()),
        BlocProvider.value(value: sl<NotificationsCubit>()),
        BlocProvider.value(value: sl<EntitlementCubit>()),
        // For the shell's ProgramWritesNotice; the workout cubit already
        // follows it from the start.
        BlocProvider.value(value: sl<ProgramListCubit>()),
      ],
      child: KeepScreenOn(
        child: DeviceFirstWeekday(
          child: FirstWeekdayListener(
            created: sl<ProgramListCubit>().firstWeekday,
            onChanged: (context, firstWeekday) => context
                .read<ProgramListCubit>()
                .changeFirstWeekday(firstWeekday),
            child: BlocListener<RestTimerCubit, RestTimerState>(
              listenWhen: (previous, current) =>
                  current.phase == RestPhase.over &&
                  previous.phase != current.phase,
              listener: (context, _) {
                final alert = context
                    .read<SettingsCubit>()
                    .state
                    .settings
                    .restTimer
                    .alert;
                if (alert.chimes) {
                  unawaited(sl<PlayRestChime>()(const NoParams()));
                }
                if (alert.vibrates) unawaited(HapticFeedback.heavyImpact());
              },
              child:
                  BlocSelector<SettingsCubit, SettingsState, ThemePreference>(
                    selector: (state) => state.settings.themePreference,
                    builder: (context, theme) => MaterialApp.router(
                      onGenerateTitle: (context) =>
                          AppLocalizations.of(context).appTitle,
                      localizationsDelegates:
                          AppLocalizations.localizationsDelegates,
                      supportedLocales: AppLocalizations.supportedLocales,
                      theme: AppPreset.shipped.lightTheme(),
                      darkTheme: AppPreset.shipped.darkTheme(),
                      themeMode: switch (theme) {
                        ThemePreference.system => ThemeMode.system,
                        ThemePreference.light => ThemeMode.light,
                        ThemePreference.dark => ThemeMode.dark,
                      },
                      routerConfig: _router,
                      builder: (context, child) => AppGate(
                        strings: appGateStrings(AppLocalizations.of(context)),
                        child: child!,
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The gate's text from the app's strings.
AppGateStrings appGateStrings(AppLocalizations l10n) => AppGateStrings(
  updateRequiredTitle: l10n.gateUpdateRequiredTitle,
  updateRequiredMessage: l10n.gateUpdateRequiredMessage,
  updateAvailableTitle: l10n.gateUpdateAvailableTitle,
  updateAvailableMessage: l10n.gateUpdateAvailableMessage,
  update: l10n.gateUpdate,
  later: l10n.gateLater,
  maintenanceTitle: l10n.gateMaintenanceTitle,
  maintenanceMessage: l10n.gateMaintenanceMessage,
  retry: l10n.gateTryAgain,
);
