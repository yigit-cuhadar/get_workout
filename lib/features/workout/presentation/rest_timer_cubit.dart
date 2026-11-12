import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/presentation/settings_cubit.dart';
import '../domain/rest.dart';
import '../domain/rest_usecases.dart';
import '../domain/workout.dart';
import '../domain/workout_lock_screen.dart';
import '../domain/workout_usecases.dart';
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

  /// Ask whether to notify when a rest is over, then answer with
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

/// The lock screen's texts for [workout] whose set to do now is [next]
/// (null: none left): that set as the workout shows it ([current]), a rest's
/// title, and that set as what follows the rest ([afterRest]).
typedef LockScreenText =
    ({String? current, String rest, String? afterRest}) Function(
      Workout workout,
      SetRef? next,
    );

/// Counts down the rest of the workout in progress, from its end time on
/// the device clock, and emits only that, so nothing else rebuilds every
/// second.
///
/// A notification for the end is scheduled only while the app is hidden
/// ([hidden]) and cancelled when it shows again ([shown]) or the rest
/// changes (which includes a user change), so it never appears over the
/// app. It needs the user's yes (`settings.restTimer.notify`); the device's
/// permission is asked only after they say yes in the app, at most once
/// per device.
///
/// It also keeps the workout in progress on the lock screen
/// ([WorkoutLockScreen]): from the moment it is in progress
/// ([ActiveWorkoutState.inProgress]) until it is finished, discarded or
/// dropped with its user, showing a running rest instead of the workout
/// while the rest timer is on in the settings. What is shown is settled
/// once the workout is loaded, so one left from an earlier run is shown
/// again or removed at start. It never alerts: a rest's end is the
/// notification's.
class RestTimerCubit extends Cubit<RestTimerState> {
  RestTimerCubit({
    required ActiveWorkoutCubit workout,
    required this._settings,
    required this._shouldAsk,
    required this._allow,
    required this._decline,
    required this._schedule,
    required this._cancel,
    required this._text,
    required this._showOnLockScreen,
    required this._clearLockScreen,
    required this._lockScreenText,
    DateTime Function()? clock,
  }) : _workout = workout,
       _clock = clock ?? DateTime.now,
       super(const RestTimerState()) {
    _status = workout.state.status;
    _rest = workout.state.rest;
    _seen = workout.state.workout;
    _subscription = workout.stream.listen(_onWorkout);
    _settingsSubscription = _settings.stream.listen((_) => _syncLockScreen());
    unawaited(_cancelNotification());
    _tick();
  }

  final ActiveWorkoutCubit _workout;
  final SettingsCubit _settings;
  final ShouldAskRestNotifications _shouldAsk;
  final AllowRestNotifications _allow;
  final DeclineRestNotifications _decline;
  final ScheduleRestNotification _schedule;
  final CancelRestNotification _cancel;
  final RestNotificationText _text;
  final ShowWorkoutOnLockScreen _showOnLockScreen;
  final ClearWorkoutFromLockScreen _clearLockScreen;
  final LockScreenText _lockScreenText;
  final DateTime Function() _clock;
  late final StreamSubscription<ActiveWorkoutState> _subscription;
  late final StreamSubscription<SettingsState> _settingsSubscription;
  late WorkoutStatus _status;
  Rest? _rest;

  /// The workout as last seen, to tell which set was ticked.
  Workout? _seen;

  /// The set ticked last in this run of the app, so the set to do now
  /// follows on from it whatever became of its rest (skipped, or none with
  /// the rest timer off). Null when unknown; then the rest's set is used.
  SetRef? _lastTicked;
  Timer? _timer;
  bool _hidden = false;

  /// Bumped whenever a scheduled notification may no longer be wanted: the
  /// rest changed or the app showed.
  int _generation = 0;

  /// Whether asking was considered in this run of the app.
  bool _considered = false;

  /// What the lock screen shows (or was last asked to), null for nothing.
  /// Unknown until the first sync, which so also replaces or removes one
  /// left from an earlier run, and again when it is to be tried again.
  LockScreenWorkout? _onLockScreen;
  bool _lockScreenKnown = false;

  /// Whether the workout was loaded since the start; until then the lock
  /// screen waits, so one left from an earlier run does not flicker.
  bool _workoutLoaded = false;

  /// Counts lock screen syncs, so only the latest one's outcome counts.
  int _lockScreenSync = 0;

  /// Whether the latest lock screen call failed (e.g. Live Activities off).
  /// The same content is not tried again until the app shows again, and the
  /// failure is logged once until a call succeeds.
  bool _lockScreenFailing = false;

  /// Lock screen calls run one after another, so the last one wins.
  Future<void> _lockScreenCalls = Future.value();

  /// How long "rest over" shows.
  static const overFor = Duration(seconds: 3);

  /// A rest that ended longer ago than this, e.g. while the app was in the
  /// background, ends without "rest over".
  static const overLate = Duration(seconds: 2);

  void _onWorkout(ActiveWorkoutState workout) {
    final wasActive = _status == WorkoutStatus.active;
    _status = workout.status;
    _followTicks(workout.workout);
    if (workout.rest == _rest) {
      _syncLockScreen();
      return;
    }
    _rest = workout.rest;
    _generation++;
    unawaited(_cancelNotification());
    _tick();
    final rest = _rest;
    // A rest kept from before the app started is not one the user started.
    if (wasActive && rest != null && rest.runsAt(_clock())) {
      unawaited(_considerAsking());
    }
    if (_hidden) unawaited(_scheduleNotification());
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
      _syncLockScreen();
      return;
    }
    final over =
        state.phase == RestPhase.running &&
        rest != null &&
        !now.isBefore(rest.endsAt) &&
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
    _syncLockScreen();
  }

  /// Puts the workout in progress, or its running rest, on the lock
  /// screen, or takes it off, when that changes.
  void _syncLockScreen() {
    final active = _workout.state;
    if (active.status == WorkoutStatus.loading && !_workoutLoaded) return;
    _workoutLoaded = true;
    final shown = _lockScreenWorkout(active);
    if (_lockScreenKnown && shown == _onLockScreen) return;
    _lockScreenKnown = true;
    _onLockScreen = shown;
    final sync = ++_lockScreenSync;
    final call = shown == null
        ? () => _clearLockScreen(const NoParams())
        : () => _showOnLockScreen(shown);
    _lockScreenCalls = _lockScreenCalls.then((_) async {
      Result<void> result;
      try {
        result = await call();
      } catch (error) {
        result = Err(UnknownFailure('$error', error));
      }
      if (sync != _lockScreenSync) return;
      final failure = result.failureOrNull;
      if (failure != null && !_lockScreenFailing) {
        Log.e('workout', 'lock screen not updated: ${failure.message}');
      }
      _lockScreenFailing = failure != null;
    });
  }

  LockScreenWorkout? _lockScreenWorkout(ActiveWorkoutState active) {
    final workout = active.workout;
    if (!active.inProgress || workout == null) return null;
    final rest = _rest;
    final text = _lockScreenText(
      workout,
      nextSet(workout, _lastTicked ?? rest?.after),
    );
    final resting =
        rest != null &&
        rest.runsAt(_clock()) &&
        _settings.state.settings.restTimer.enabled;
    return LockScreenWorkout(
      name: workout.name,
      startedAt: workout.startedAt,
      current: text.current,
      rest: resting
          ? RestCountdown(
              endsAt: rest.endsAt,
              title: text.rest,
              detail: text.afterRest,
            )
          : null,
    );
  }

  void _followTicks(Workout? now) {
    final before = _seen;
    _seen = now;
    if (now == null || before == null || before.id != now.id) {
      _lastTicked = null;
      return;
    }
    final ticked = newlyDone(before, now);
    if (ticked != null) {
      _lastTicked = ticked;
      return;
    }
    // An edit may have moved sets or unticked it: keep it only while it
    // still names a done set.
    final last = _lastTicked;
    final set = last == null
        ? null
        : now.exercises
              .elementAtOrNull(last.exercise)
              ?.sets
              .elementAtOrNull(last.set);
    if (set == null || !set.done) _lastTicked = null;
  }

  /// The app went to the background: notify at the end of a running rest.
  void hidden() {
    _hidden = true;
    unawaited(_scheduleNotification());
  }

  /// The app is in front again.
  void shown() {
    _hidden = false;
    _generation++;
    unawaited(_cancelNotification());
    if (_lockScreenFailing) _lockScreenKnown = false;
    _tick();
  }

  /// The user's answer to [RestTimerState.askNotify]. "Not now" is
  /// remembered on this device only, so other devices still ask; a yes is
  /// the user's, on every device.
  Future<void> answerNotify({required bool allow}) async {
    emit(state.copyWith(askNotify: false));
    if (allow) {
      await setNotify(true);
    } else {
      await _decline(const NoParams());
    }
  }

  /// The user turns the rest notification on (asking this device for
  /// permission) or off, on every device. Returns whether this device will
  /// notify.
  Future<bool> setNotify(bool on) async {
    _storeWish(on);
    if (!on) return false;
    final granted = await _allow(const NoParams());
    if (granted.failureOrNull case final failure?) {
      Log.e('rest', 'notification permission not asked: ${failure.message}');
    }
    final allowed = granted.valueOrNull ?? false;
    // On Android the countdown needs the permission: show it now.
    if (allowed && !isClosed) {
      _lockScreenKnown = false;
      _syncLockScreen();
    }
    return allowed;
  }

  Future<void> _considerAsking() async {
    if (_considered) return;
    _considered = true;
    if (await _shouldAsk(_settings.state.settings.restTimer.notify) &&
        !isClosed) {
      emit(state.copyWith(askNotify: true));
    }
  }

  void _storeWish(bool notify) {
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

  Future<void> _scheduleNotification() async {
    final rest = _rest;
    final workout = _workout.state.workout;
    if (rest == null ||
        workout == null ||
        !rest.runsAt(_clock()) ||
        _settings.state.settings.restTimer.notify != true) {
      return;
    }
    final generation = _generation;
    final text = _text(workout, nextSet(workout, rest.after));
    final result = await _schedule((
      at: rest.endsAt,
      title: text.title,
      body: text.body,
    ));
    if (result.failureOrNull case final failure?) {
      Log.e('rest', 'rest notification not scheduled: ${failure.message}');
      return;
    }
    // The rest changed, the user changed or the app came back meanwhile,
    // and that cancel may have run before this schedule took effect.
    if (isClosed || !_hidden || generation != _generation) {
      await _cancelNotification();
    }
  }

  Future<void> _cancelNotification() async {
    final result = await _cancel(const NoParams());
    if (result.failureOrNull case final failure?) {
      Log.e('rest', 'rest notification not cancelled: ${failure.message}');
    }
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    await _subscription.cancel();
    await _settingsSubscription.cancel();
    return super.close();
  }
}
