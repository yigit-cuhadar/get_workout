import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';

import '../features/body/body_module.dart';
import '../features/account/presentation/consent_cubit.dart';
import '../features/account/presentation/delete_account_cubit.dart';
import '../features/exercises/presentation/body_model_cubit.dart';
import '../features/exercises/presentation/equipment_cubit.dart';
import '../features/exercises/presentation/exercise_catalogue_cubit.dart';
import '../features/profile/presentation/profile_cubit.dart';
import '../features/profile/presentation/profile_form_cubit.dart';
import '../features/programs/presentation/program_list_cubit.dart';
import '../features/exercises/presentation/favorites_cubit.dart';
import '../features/notifications/data/notification_payloads.dart';
import '../features/notifications/presentation/notifications_cubit.dart';
import '../features/settings/domain/user_settings.dart';
import '../features/settings/presentation/settings_cubit.dart';
import '../features/workout/domain/workout_usecases.dart';
import '../features/workout/presentation/active_workout_cubit.dart';
import '../features/workout/presentation/rest_timer_cubit.dart';
import '../features/subscription/presentation/purchaser_session.dart';
import '../features/subscription/subscription_module.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';

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
    skippedOnboarding: sl<SkippedOnboarding>(),
    profileDebugSection: SubscriptionModule.debugControls(sl),
  );
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<String?> _taps;
  late final StreamSubscription<void> _lockScreenTaps;

  /// A tapped notification or lock-screen activity, until the app is past
  /// its start: where it leads with the open pages ([openLocations]; null:
  /// stay), and whether it is pushed onto them rather than gone to.
  ({String? Function(List<String> open) to, bool push})? _tapped;

  @override
  void initState() {
    super.initState();
    // Created now so the store follows the user from the first auth event.
    final purchaser = sl<PurchaserSession>();
    final rest = sl<RestTimerCubit>();
    BodyModule.startPhotoBackup(sl);
    // Created now so reminders follow the user from the first auth event.
    final notifications = sl<NotificationsCubit>();
    _router.routerDelegate.addListener(_openTapped);
    _taps = sl<NotificationTaps>().stream.listen((payload) {
      if (payload == NotificationPayloads.activeWorkout) {
        unawaited(_openLockScreenTap());
      } else if (NotificationPayloads.targetOf(payload) case final target?) {
        _openNotification(target);
      }
    });
    _lockScreenTaps = sl<WatchLockScreenTaps>()().listen(
      (_) => unawaited(_openLockScreenTap()),
    );
    _lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(sl<ExerciseCatalogueCubit>().appResumed());
        purchaser.resume();
        BodyModule.resumed(sl);
        unawaited(notifications.resumed());
      },
      onHide: rest.hidden,
      onShow: rest.shown,
    );
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
    _router.routerDelegate.removeListener(_openTapped);
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
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
      child: BlocListener<RestTimerCubit, RestTimerState>(
        listenWhen: (previous, current) =>
            current.phase == RestPhase.over && previous.phase != current.phase,
        listener: (_, _) => unawaited(HapticFeedback.heavyImpact()),
        child: BlocSelector<SettingsCubit, SettingsState, ThemePreference>(
          selector: (state) => state.settings.themePreference,
          builder: (context, theme) => MaterialApp.router(
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ForgeTheme.light(),
            darkTheme: ForgeTheme.dark(),
            themeMode: switch (theme) {
              ThemePreference.system => ThemeMode.system,
              ThemePreference.light => ThemeMode.light,
              ThemePreference.dark => ThemeMode.dark,
            },
            routerConfig: _router,
          ),
        ),
      ),
    );
  }
}
