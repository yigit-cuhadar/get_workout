import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/device_localizations.dart';
import '../notifications/data/notification_payloads.dart';
import '../programs/domain/completed_days.dart';
import '../settings/presentation/settings_section.dart';
import 'data/android_workout_lock_screen.dart';
import 'data/audio_rest_chime.dart';
import 'data/device_rest_notifications.dart';
import 'data/device_workout_end_notice.dart';
import 'data/file_local_workout_store.dart';
import 'data/firestore_workout_repository.dart';
import 'data/ios_workout_lock_screen.dart';
import 'data/workout_completed_days.dart';
import 'domain/history_usecases.dart';
import 'domain/rest.dart';
import 'domain/rest_chime.dart';
import 'domain/rest_notifications.dart';
import 'domain/rest_usecases.dart';
import 'domain/workout_lock_screen.dart';
import 'domain/workout_editing.dart';
import 'domain/workout_end_notice.dart';
import 'domain/workout_repository.dart';
import 'domain/workout_usecases.dart';
import 'presentation/active_workout_cubit.dart';
import 'presentation/rest_timer_cubit.dart';
import 'presentation/workout_text.dart';
import 'presentation/workout_detail_cubit.dart';
import 'presentation/workout_edit_cubit.dart';

/// Registers the workout feature. Needs `AuthModule`, `SettingsModule`,
/// `NotificationsModule`, `ExercisesModule`, `CalculatorsModule` (the
/// plate breakdown) and `ProgramsModule`, which
/// takes [completedDays] for its plan.
class WorkoutModule implements FeatureModule {
  const WorkoutModule();

  /// The program days done, from the stored workouts.
  static CompletedDays completedDays(GetIt sl) => WorkoutCompletedDays(sl());

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<WorkoutRepository>(
        () => FirestoreWorkoutRepository(FirebaseFirestore.instance),
      )
      // App support files are private and not shown to the user.
      ..registerLazySingleton<LocalWorkoutStore>(
        () => FileLocalWorkoutStore(getApplicationSupportDirectory),
      )
      ..registerLazySingleton<RestNotifications>(
        () => DeviceRestNotifications(
          sl.getAsync<Notifications>(),
          getApplicationSupportDirectory,
          sl(),
          channelName: (alert) {
            final l10n = deviceLocalizations();
            return l10n.restChannelName(l10n.restAlertLabel(alert));
          },
          channelDescription: deviceLocalizations().restChannelDescription,
        ),
      )
      ..registerLazySingleton<RestChime>(AudioRestChime.new)
      ..registerLazySingleton<WorkoutLockScreen>(
        () => defaultTargetPlatform == TargetPlatform.iOS
            ? IosWorkoutLockScreen(
                restButtons: () {
                  final l10n = deviceLocalizations();
                  final seconds = restExtension.inSeconds;
                  return (
                    shorten: l10n.lockScreenRestShorten(seconds),
                    extend: l10n.restAdd(seconds),
                    skip: l10n.lockScreenRestSkip,
                  );
                },
              )
            : AndroidWorkoutLockScreen(
                sl.getAsync<Notifications>(),
                payload: NotificationPayloads.activeWorkout,
              ),
      )
      ..registerFactory(() => ShowWorkoutOnLockScreen(sl()))
      ..registerFactory(() => ClearWorkoutFromLockScreen(sl()))
      ..registerFactory(() => WatchLockScreenTaps(sl()))
      ..registerFactory(() => WatchLockScreenRestActions(sl()))
      ..registerFactory(() => ShouldAskRestNotifications(sl()))
      ..registerFactory(() => AllowRestNotifications(sl()))
      ..registerFactory(() => DeclineRestNotifications(sl()))
      ..registerFactory(() => PlayRestChime(sl()))
      ..registerFactory(() => ScheduleRestNotification(sl()))
      ..registerFactory(() => CancelRestNotification(sl()))
      ..registerFactory(() => LoadLocalWorkouts(sl()))
      ..registerFactory(() => KeepLocalWorkouts(sl()))
      ..registerFactory(() => ConfirmStoredWorkout(sl()))
      ..registerFactory(() => RebuildExerciseStats(sl()))
      ..registerFactory(() => NewWorkoutId(sl()))
      ..registerFactory(() => WatchExerciseStats(sl()))
      ..registerFactory(() => GetHeldRecords(sl()))
      ..registerFactory(() => WatchAllExerciseStats(sl()))
      ..registerFactory(() => FinishWorkout(sl()))
      ..registerLazySingleton<WorkoutEndNotice>(
        () => DeviceWorkoutEndNotice(sl.getAsync<Notifications>()),
      )
      ..registerFactory(() => ScheduleWorkoutEndNotice(sl()))
      ..registerFactory(() => CancelWorkoutEndNotice(sl()))
      ..registerFactory(() => SaveWorkoutAsProgram(sl()))
      ..registerFactory(() => UpdateProgramDay(sl()))
      // One workout in progress for the whole app.
      ..registerLazySingleton(
        () => ActiveWorkoutCubit(
          watchAuthUser: sl(),
          loadLocal: sl(),
          keepLocal: sl(),
          confirmStored: sl(),
          rebuildStats: sl(),
          newWorkoutId: sl(),
          watchStats: sl(),
          finishWorkout: sl(),
          saveAsProgram: sl(),
          updateProgramDay: sl(),
          programs: sl(),
          catalogue: sl(),
          watchSettings: sl(),
          loadPlates: sl(),
          scheduleEndNotice: sl(),
          cancelEndNotice: sl(),
          endText: (workout, lastSetAt) {
            final l10n = deviceLocalizations();
            if (lastSetAt == null) {
              return (
                title: l10n.workoutSelfDiscardedTitle(workout.name),
                body: l10n.workoutSelfDiscardedBody,
              );
            }
            return (
              title: l10n.workoutSelfEndedTitle(
                workout.name,
                DateFormat.jm(l10n.localeName).format(lastSetAt),
              ),
              body: l10n.workoutSelfEndedBody(
                l10n.durationMinutes(lastSetAt.difference(workout.startedAt)),
              ),
            );
          },
        ),
      )
      ..registerLazySingleton(
        () => RestTimerCubit(
          workout: sl(),
          settings: sl(),
          shouldAsk: sl(),
          allow: sl(),
          decline: sl(),
          schedule: sl(),
          cancel: sl(),
          text: (workout, next) {
            final l10n = deviceLocalizations();
            return (
              title: l10n.restOver,
              body: next == null
                  ? l10n.restNotificationBack
                  : l10n.restNextText(
                      workout.exercises[next.exercise],
                      next.set,
                    ),
            );
          },
          showOnLockScreen: sl(),
          clearLockScreen: sl(),
          lockScreenText: (active, next, unit) {
            final l10n = deviceLocalizations();
            final rest = l10n.restLockScreenTitle;
            final workout = active.workout!;
            if (next == null) {
              return (current: null, set: null, rest: rest, afterRest: null);
            }
            final exercise = workout.exercises[next.exercise];
            return (
              current: l10n.setToDo(exercise, next.set),
              set: l10n.lockScreenSet(
                workout,
                next,
                active.suggestion(next),
                unit,
              ),
              rest: rest,
              afterRest: l10n.restNextText(exercise, next.set),
            );
          },
          watchRestActions: sl(),
        ),
      )
      ..registerFactory(() => WatchWorkoutsBetween(sl()))
      ..registerFactory(() => WatchStoredWorkout(sl()))
      ..registerFactory(() => WatchRejectedWorkoutEdits(sl()))
      ..registerFactory(() => SaveWorkoutChange(sl()))
      ..registerFactoryParam<WorkoutDetailCubit, String, void>(
        (id, _) => WorkoutDetailCubit(
          id: id,
          getCurrentUser: sl(),
          watchAuthUser: sl(),
          watchWorkout: sl(),
          saveChange: sl(),
          changed: sl<ActiveWorkoutCubit>().storedWorkoutChanged,
          getRecords: sl(),
        ),
      )
      // A stored workout's id, or none and the name of a new past workout.
      ..registerFactoryParam<WorkoutEditCubit, String?, PastWorkoutPlan>(
        (id, plan) => WorkoutEditCubit(
          id: id,
          plan: plan,
          getCurrentUser: sl(),
          watchAuthUser: sl(),
          watchWorkout: sl(),
          newWorkoutId: sl(),
          saveChange: sl(),
          changed: sl<ActiveWorkoutCubit>().storedWorkoutChanged,
          catalogue: sl(),
        ),
      );
  }
}
