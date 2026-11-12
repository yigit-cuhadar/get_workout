import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';

import '../features/exercises/presentation/body_model_cubit.dart';
import '../features/exercises/presentation/equipment_cubit.dart';
import '../features/exercises/presentation/exercise_catalogue_cubit.dart';
import '../features/profile/presentation/profile_cubit.dart';
import '../features/programs/presentation/program_list_cubit.dart';
import '../features/exercises/presentation/favorites_cubit.dart';
import '../features/notifications/data/notification_taps.dart';
import '../features/notifications/presentation/notifications_cubit.dart';
import '../features/settings/domain/user_settings.dart';
import '../features/settings/presentation/settings_cubit.dart';
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
    profileDebugSection: SubscriptionModule.debugControls(sl),
  );
  late final AppLifecycleListener _lifecycle;

  /// Where a tapped notification leads, until the app is past its start.
  String? _tapped;

  @override
  void initState() {
    super.initState();
    // Created now so the store follows the user from the first auth event.
    final purchaser = sl<PurchaserSession>();
    final rest = sl<RestTimerCubit>();
    // Created now so reminders follow the user from the first auth event.
    final notifications = sl<NotificationsCubit>();
    _router.routerDelegate.addListener(_openTapped);
    sl<NotificationTaps>().listen(_openNotification);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(sl<ExerciseCatalogueCubit>().appResumed());
        purchaser.resume();
        unawaited(notifications.resumed());
      },
      onHide: rest.hidden,
      onShow: rest.shown,
    );
  }

  void _openNotification(NotificationTarget target) {
    _tapped = switch (target) {
      NotificationTarget.workout ||
      NotificationTarget.announcement => Routes.today,
      // The measurement flow is being built elsewhere; until it is merged,
      // its reminder opens the Progress tab.
      NotificationTarget.measurement => Routes.progress,
    };
    _openTapped();
  }

  void _openTapped() {
    final location = _tapped;
    if (location == null ||
        !isPastStart(_router.routerDelegate.currentConfiguration.uri.path)) {
      return;
    }
    _tapped = null;
    _router.go(location);
  }

  @override
  void dispose() {
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
