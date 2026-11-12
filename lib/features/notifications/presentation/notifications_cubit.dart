import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/user_stream_follower.dart';
import '../../body/domain/body_usecases.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/completed_days.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_schedule.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../../settings/domain/settings_usecases.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/notification_repository.dart';
import '../domain/notifications_usecases.dart';
import '../domain/reminder_plan.dart';

class NotificationsState extends Equatable {
  const NotificationsState({this.allowed});

  /// Whether the device lets the app notify; null until known.
  final bool? allowed;

  @override
  List<Object?> get props => [allowed];
}

typedef NotificationText = ({String title, String body});

/// Keeps the device's reminders matching the signed-in user's reminder
/// settings and active program, and follows the announcements of the
/// device's language once the device lets the app notify.
///
/// Reminders are planned again whenever the program list (program, its
/// weekdays, the schedule, done days), the user's settings or their
/// measurement days (a reminder is skipped on a day already measured)
/// change, on
/// every user change and on [resumed]. What is not known yet is left as it
/// is: the workout reminders while the programs load or the premium status
/// of a premium copy is unknown, the measurement reminders while the
/// measurement days load, all reminders while the user's settings
/// load, so an app start never drops them. A change of user drops the
/// previous user's at once.
class NotificationsCubit extends Cubit<NotificationsState> {
  NotificationsCubit({
    required WatchAuthUser watchAuthUser,
    required WatchSettings watchSettings,
    required WatchMeasuredDates watchMeasured,
    required ProgramListCubit programs,
    required this._planWorkout,
    required this._planMeasurement,
    required this._sync,
    required this._getAccess,
    required this._requestAccess,
    required this._openSettings,
    required this._refreshTimeZone,
    required this._followAnnouncements,
    required this._workoutText,
    required this._measurementText,
    required this._language,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _programs = programs.state,
       super(const NotificationsState()) {
    _programSubscription = programs.stream.listen((state) {
      _programs = state;
      _resync();
    });
    _settings = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchSettings.call,
      onUser: _onUser,
      onData: (settings) {
        _userSettings = settings;
        _resync();
      },
      logTag: 'notifications',
    );
    _measuredDates = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchMeasured.call,
      onUser: (_) => _measured = null,
      onData: (measured) {
        _measured = measured;
        _resync();
      },
      logTag: 'notifications',
    );
    unawaited(_checkAccess());
  }

  final PlanWorkoutReminders _planWorkout;
  final PlanMeasurementReminders _planMeasurement;
  final SyncReminders _sync;
  final GetNotificationAccess _getAccess;
  final RequestNotificationAccess _requestAccess;
  final OpenNotificationSettings _openSettings;
  final RefreshTimeZone _refreshTimeZone;
  final FollowAnnouncements _followAnnouncements;
  final NotificationText Function(WorkoutReminder reminder) _workoutText;
  final NotificationText Function() _measurementText;

  /// The language code announcements follow.
  final String Function() _language;
  final DateTime Function() _clock;
  late final StreamSubscription<ProgramListState> _programSubscription;
  late final UserStreamFollower<UserSettings> _settings;
  late final UserStreamFollower<Set<CalendarDate>> _measuredDates;

  /// The dates the current user already measured on; null until known.
  Set<CalendarDate>? _measured;
  ProgramListState _programs;

  /// The current user's settings; null until they arrive.
  UserSettings? _userSettings;
  var _sawUser = false;

  /// The language whose announcements are followed.
  String? _followed;

  /// Syncs run one after another, each on the latest inputs.
  Future<void> _queue = Future.value();
  var _resyncQueued = false;

  void _onUser(String? uid) {
    _userSettings = null;
    // The first user at start is the one the reminders were made for.
    if (_sawUser || uid == null) _enqueue(_clear);
    _sawUser = true;
  }

  /// The app is in front again: the day, the time zone or the device's
  /// permission may have changed meanwhile.
  Future<void> resumed() async {
    final zone = await _refreshTimeZone(const NoParams());
    if (zone.failureOrNull case final failure?) {
      Log.e('notifications', 'time zone not refreshed: ${failure.message}');
    }
    _resync();
    await _checkAccess();
  }

  /// Asks the device to let the app notify, unless it already does; whether
  /// it does.
  Future<bool> allow() async {
    if (state.allowed == true) return true;
    final result = await _requestAccess(const NoParams());
    if (result.failureOrNull case final failure?) {
      Log.e('notifications', 'permission not asked: ${failure.message}');
    }
    final allowed = result.valueOrNull ?? false;
    if (!isClosed) emit(NotificationsState(allowed: allowed));
    // Following needs the network; the answer must not wait for it.
    if (allowed) unawaited(_follow());
    return allowed;
  }

  Future<void> openSettings() async {
    final result = await _openSettings(const NoParams());
    if (result.failureOrNull case final failure?) {
      Log.e('notifications', 'settings not opened: ${failure.message}');
    }
  }

  Future<void> _checkAccess() async {
    final result = await _getAccess(const NoParams());
    if (result.failureOrNull case final failure?) {
      Log.e('notifications', 'permission unknown: ${failure.message}');
    }
    final allowed = result.valueOrNull;
    if (isClosed) return;
    emit(NotificationsState(allowed: allowed));
    if (allowed == true) await _follow();
  }

  Future<void> _follow() async {
    final language = _language();
    if (_followed == language) return;
    _followed = language;
    final result = await _followAnnouncements(language);
    if (result.failureOrNull case final failure?) {
      _followed = null;
      Log.e('notifications', 'announcements not followed: ${failure.message}');
    }
  }

  void _resync() {
    if (_resyncQueued) return;
    _resyncQueued = true;
    _enqueue(() {
      _resyncQueued = false;
      return _syncNow();
    });
  }

  void _enqueue(Future<void> Function() job) => _queue = _queue
      .then((_) => job())
      .catchError((Object error, StackTrace stack) {
        Log.e('notifications', 'reminders not synced', error, stack);
      });

  Future<void> _syncNow() async {
    final settings = _userSettings;
    if (settings == null) return;
    final now = _clock();
    // Turned off is cleared whatever is known about the programs.
    if (!settings.workoutReminder.enabled) {
      await _syncKind(ReminderKind.workout, const []);
    } else if (_workoutInput(settings, now) case final workout?) {
      await _syncKind(ReminderKind.workout, [
        for (final reminder in _planWorkout(workout))
          _notice(reminder.id, reminder.at, _workoutText(reminder)),
      ]);
    }
    if (!settings.measurementReminder.enabled) {
      await _syncKind(ReminderKind.measurement, const []);
    } else if (_measured case final measured?) {
      await _syncKind(ReminderKind.measurement, [
        for (final reminder in _planMeasurement((
          settings: settings.measurementReminder,
          measured: measured,
          now: now,
        )))
          _notice(reminder.id, reminder.at, _measurementText()),
      ]);
    }
  }

  /// Null while the workout reminders cannot be known.
  WorkoutReminderInput? _workoutInput(UserSettings settings, DateTime now) {
    final programs = _programs;
    if (programs.status != ProgramListStatus.ready) return null;
    final program = programs.activeProgram;
    final access = program == null ? null : programs.access(program);
    if (access == ProgramAccess.waiting) return null;
    return (
      settings: settings.workoutReminder,
      active: programs.active,
      program: program,
      done: [
        for (final day in programs.weekPlan)
          if (day.status == PlannedStatus.done)
            CompletedDay(date: day.date, dayIndex: day.dayIndex),
      ],
      open: access == ProgramAccess.open,
      now: now,
    );
  }

  Future<void> _clear() async {
    for (final kind in ReminderKind.values) {
      await _syncKind(kind, const []);
    }
  }

  Future<void> _syncKind(ReminderKind kind, List<ReminderNotice> wanted) async {
    final result = await _sync((kind: kind, wanted: wanted));
    if (result.failureOrNull case final failure?) {
      Log.e('notifications', '${kind.name} reminders: ${failure.message}');
    }
  }

  static ReminderNotice _notice(int id, DateTime at, NotificationText text) =>
      (id: id, at: at, title: text.title, body: text.body);

  @override
  Future<void> close() async {
    await _programSubscription.cancel();
    await _settings.cancel();
    await _measuredDates.cancel();
    return super.close();
  }
}
