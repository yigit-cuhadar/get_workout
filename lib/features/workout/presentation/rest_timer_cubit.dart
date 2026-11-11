import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';

import '../../settings/presentation/settings_cubit.dart';
import '../domain/rest.dart';
import '../domain/workout.dart';
import 'active_workout_cubit.dart';

enum RestPhase {
  none,
  running,

  /// Just reached zero in front of the user; shown for
  /// [RestTimerCubit.overFor], then [none].
  over,
}

class RestTimerState extends Equatable {
  const RestTimerState({
    this.phase = RestPhase.none,
    this.remainingS = 0,
    this.askNotify = false,
  });

  final RestPhase phase;

  /// Whole seconds left, rounded up, while [RestPhase.running].
  final int remainingS;

  /// Ask once whether to notify when a rest is over, then answer with
  /// [RestTimerCubit.answerNotify].
  final bool askNotify;

  RestTimerState copyWith({
    RestPhase? phase,
    int? remainingS,
    bool? askNotify,
  }) => RestTimerState(
    phase: phase ?? this.phase,
    remainingS: remainingS ?? this.remainingS,
    askNotify: askNotify ?? this.askNotify,
  );

  @override
  List<Object?> get props => [phase, remainingS, askNotify];
}

/// The notification's text for a rest of [workout] after which [next]
/// (null: none left) is due.
typedef RestNotificationText = ({String title, String body}) Function(
  Workout workout,
  SetRef? next,
);

/// Counts down the rest of the workout in progress, from its end time on
/// the device clock, and emits only that, so nothing else rebuilds every
/// second.
///
/// A notification for the end is scheduled only while the app is hidden
/// ([hidden]) and cancelled when it shows again ([shown]) or the rest
/// changes, so it never appears over the app. It needs the user's yes,
/// asked the first time a rest starts and stored in the settings.
class RestTimerCubit extends Cubit<RestTimerState> {
  RestTimerCubit({
    required ActiveWorkoutCubit workout,
    required this._settings,
    required this._notifications,
    required this._text,
    DateTime Function()? clock,
  }) : _workout = workout,
       _clock = clock ?? DateTime.now,
       super(const RestTimerState()) {
    _status = workout.state.status;
    _rest = workout.state.rest;
    _subscription = workout.stream.listen(_onWorkout);
    unawaited(_cancelNotification());
    _tick();
  }

  final ActiveWorkoutCubit _workout;
  final SettingsCubit _settings;
  final Future<Notifications> _notifications;
  final RestNotificationText _text;
  final DateTime Function() _clock;
  late final StreamSubscription<ActiveWorkoutState> _subscription;
  late WorkoutStatus _status;
  Rest? _rest;
  Timer? _timer;
  bool _hidden = false;

  /// Whether the user was asked, or their yes checked against the device's
  /// permission, in this run of the app.
  bool _asked = false;

  /// The rest notification's id; other notifications use others.
  static const notificationId = 1;

  /// How long "rest over" shows.
  static const overFor = Duration(seconds: 3);

  /// A rest that ended longer ago than this, e.g. while the app was in the
  /// background, ends without "rest over".
  static const overLate = Duration(seconds: 2);

  void _onWorkout(ActiveWorkoutState workout) {
    final wasActive = _status == WorkoutStatus.active;
    _status = workout.status;
    if (workout.rest == _rest) return;
    _rest = workout.rest;
    _timer?.cancel();
    unawaited(_cancelNotification());
    _tick();
    final rest = _rest;
    // A rest kept from before the app started is not one the user started.
    if (wasActive && rest != null && rest.runsAt(_clock())) {
      unawaited(_askOrCheck());
    }
    if (_hidden) unawaited(_schedule());
  }

  void _tick() {
    _timer?.cancel();
    final rest = _rest;
    final now = _clock();
    if (rest != null && rest.runsAt(now)) {
      final left = rest.endsAt.difference(now);
      final seconds = (left.inMicroseconds / Duration.microsecondsPerSecond)
          .ceil();
      emit(state.copyWith(phase: RestPhase.running, remainingS: seconds));
      // Again when the shown second changes.
      _timer = Timer(left - Duration(seconds: seconds - 1), _tick);
      return;
    }
    final over =
        state.phase == RestPhase.running &&
        rest != null &&
        now.difference(rest.endsAt) <= overLate;
    emit(
      state.copyWith(
        phase: over ? RestPhase.over : RestPhase.none,
        remainingS: 0,
      ),
    );
    if (over) {
      _timer = Timer(
        overFor,
        () => emit(state.copyWith(phase: RestPhase.none)),
      );
    }
  }

  /// The app went to the background: notify at the end of a running rest.
  void hidden() {
    _hidden = true;
    unawaited(_schedule());
  }

  /// The app is in front again.
  void shown() {
    _hidden = false;
    unawaited(_cancelNotification());
    _tick();
  }

  /// The user's answer to [RestTimerState.askNotify].
  Future<void> answerNotify({required bool allow}) async {
    emit(state.copyWith(askNotify: false));
    if (allow) {
      await setNotify(true);
    } else {
      _storeNotify(false);
    }
  }

  /// Turns the rest notification on, asking the device for permission
  /// (and, on Android, for exact alarms, without which it comes late), or
  /// off. Returns whether it is on.
  Future<bool> setNotify(bool on) async {
    if (!on) {
      _storeNotify(false);
      return false;
    }
    final notifications = await _notifications;
    final granted =
        (await notifications.request()).valueOrNull ==
        NotificationPermission.granted;
    if (granted &&
        (await notifications.canScheduleExact()).valueOrNull == false) {
      // Without it the notification falls back to an inexact alarm.
      await notifications.requestExact();
    }
    _storeNotify(granted);
    return granted;
  }

  /// Asks once whether to notify; after a yes, checks once that the device
  /// still allows it (another device may have said yes), asking the device
  /// if not and storing a no.
  Future<void> _askOrCheck() async {
    if (_asked) return;
    _asked = true;
    switch (_settings.state.settings.restTimer.notify) {
      case null:
        emit(state.copyWith(askNotify: true));
      case true:
        final notifications = await _notifications;
        final status = await notifications.status();
        if (status.valueOrNull != NotificationPermission.denied) return;
        await setNotify(true);
      case false:
        return;
    }
  }

  void _storeNotify(bool notify) {
    final settings = _settings.state.settings;
    if (settings.restTimer.notify == notify) return;
    unawaited(
      _settings.update(
        settings.copyWith(
          restTimer: settings.restTimer.copyWith(notify: notify),
        ),
      ),
    );
  }

  Future<void> _schedule() async {
    final rest = _rest;
    final workout = _workout.state.workout;
    if (rest == null ||
        workout == null ||
        !rest.runsAt(_clock()) ||
        _settings.state.settings.restTimer.notify != true) {
      return;
    }
    final text = _text(workout, nextSet(workout, rest.after));
    final notifications = await _notifications;
    // The rest may have changed, or the app come back, meanwhile.
    if (!_hidden || _rest != rest || isClosed) return;
    final result = await notifications.scheduleAt(
      notificationId,
      rest.endsAt,
      title: text.title,
      body: text.body,
    );
    if (result.failureOrNull case final failure?) {
      Log.e('rest', 'rest notification not scheduled: ${failure.message}');
    }
  }

  Future<void> _cancelNotification() async {
    final result = await (await _notifications).cancel(notificationId);
    if (result.failureOrNull case final failure?) {
      Log.e('rest', 'rest notification not cancelled: ${failure.message}');
    }
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    await _subscription.cancel();
    return super.close();
  }
}
