import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/domain/user_settings.dart';
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

/// What the workout's bottom panel shows.
enum WorkoutPanel {
  /// The effort of the set just ticked.
  question,

  /// The rest's countdown.
  rest,

  /// The moment the rest ended.
  restOver,

  /// Every set is done: Finish workout.
  finish,

  /// The selected set's values, under the rest's line while one runs.
  entry,
}

/// The panel while the effort question is [asking] or not, [allDone] the
/// workout's sets, the rest in [phase]: the question first; the rest while
/// the set to do waits for it ([entryWaitsForRest]) or nothing is left to
/// do; then Finish workout once every set is done, unless a done set was
/// picked ([doneSetPicked]); else the selected set.
WorkoutPanel workoutPanel({
  required bool asking,
  required bool entryWaitsForRest,
  required bool allDone,
  required bool doneSetPicked,
  required RestPhase phase,
}) {
  if (asking) return WorkoutPanel.question;
  final finish = allDone && !doneSetPicked;
  if (entryWaitsForRest || finish) {
    if (phase == RestPhase.running) return WorkoutPanel.rest;
    if (phase == RestPhase.over) return WorkoutPanel.restOver;
  }
  return finish ? WorkoutPanel.finish : WorkoutPanel.entry;
}

class RestTimerState extends Equatable {
  const RestTimerState({
    this.phase = RestPhase.none,
    this.remainingS = 0,
    this.totalS = 0,
  });

  final RestPhase phase;

  /// Whole seconds left, rounded up, while [RestPhase.running].
  final int remainingS;

  /// The whole rest in seconds while [RestPhase.running], "+15 s"
  /// included, so the part already passed can be shown.
  final int totalS;

  /// How much of the running rest has passed, from 0 to 1.
  double get progress => totalS == 0 ? 0 : 1 - remainingS / totalS;

  RestTimerState copyWith({RestPhase? phase, int? remainingS, int? totalS}) =>
      RestTimerState(
        phase: phase ?? this.phase,
        remainingS: remainingS ?? this.remainingS,
        totalS: totalS ?? this.totalS,
      );

  @override
  List<Object?> get props => [phase, remainingS, totalS];
}

/// The notification's text for a rest of [workout] after which [next]
/// (null: none left) is due.
typedef RestNotificationText = ({String title, String body}) Function(
  Workout workout,
  SetRef? next,
);

/// The lock screen's texts for the workout of [active] whose set to do now
/// is [next] (null: none left), weights in [unit]: that set on one line
/// ([current]) and in parts ([set]), a rest's title, and that set as what
/// follows the rest ([afterRest]).
typedef LockScreenText =
    ({String? current, LockScreenSet? set, String rest, String? afterRest})
    Function(ActiveWorkoutState active, SetRef? next, WeightUnit unit);

/// Counts down the rest of the workout in progress, from its end time on
/// the device clock, and emits only that, so nothing else rebuilds every
/// second.
///
/// A notification for the end is scheduled only while the app is hidden
/// ([hidden]), moved with the rest meanwhile (+15 s from the lock screen),
/// and cancelled when the app shows again ([shown]) or the rest ends
/// (which includes a user change), so it never appears over the app. It needs the user's yes (`settings.restTimer.notify`); the device's
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
/// notification's. Its rest buttons (−15 s, +15 s, Skip) change the rest
/// of the workout in progress, once it is loaded.
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
    required WatchLockScreenRestActions watchRestActions,
    DateTime Function()? clock,
  }) : _workout = workout,
       _clock = clock ?? DateTime.now,
       super(const RestTimerState()) {
    _rest = workout.state.rest;
    _seen = workout.state.workout;
    _subscription = workout.stream.listen(_onWorkout);
    _settingsSubscription = _settings.stream.listen((_) => _syncLockScreen());
    _restActions = watchRestActions().listen(
      (press) => unawaited(_onRestPress(press)),
    );
    _settleNotification();
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
  late final StreamSubscription<LockScreenRestPress> _restActions;
  Rest? _rest;

  /// [RestTimerState.totalS] of the running rest; null until its first
  /// tick.
  int? _restTotalS;

  /// The workout as last seen, to tell which set was ticked.
  Workout? _seen;

  /// The set ticked last in this run of the app, so the set to do now
  /// follows on from it whatever became of its rest (skipped, or none with
  /// the rest timer off). Null when unknown; then the rest's set is used.
  SetRef? _lastTicked;
  Timer? _timer;
  bool _hidden = false;

  /// Calls on the rest notification run one after another, each settling
  /// it as things are when it runs, so the last one wins.
  Future<void> _notificationCalls = Future.value();

  /// The notification scheduled last, until it is cancelled.
  RestNotice? _scheduled;

  /// Whether one may be pending: unknown at start (one left from an
  /// earlier run), and from each schedule until a cancel.
  bool _mayBePending = true;

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
    _followTicks(workout.workout);
    if (workout.rest == _rest) {
      _syncLockScreen();
      return;
    }
    _restTotalS = _totalAfter(_rest, workout.rest);
    _rest = workout.rest;
    _settleNotification();
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    final rest = _rest;
    final now = _clock();
    if (rest != null && rest.runsAt(now)) {
      final left = rest.endsAt.difference(now);
      final seconds = (left.inMicroseconds / Duration.microsecondsPerSecond)
          .ceil();
      emit(
        state.copyWith(
          phase: RestPhase.running,
          remainingS: seconds,
          totalS: _restTotalS ??= seconds,
        ),
      );
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
        totalS: 0,
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

  /// The whole of [next] once it replaces [previous]: the same rest moved
  /// (±15 s, or unlinked from its set) keeps its start; any other counts
  /// from its first tick (null).
  int? _totalAfter(Rest? previous, Rest? next) {
    final total = _restTotalS;
    if (total == null ||
        previous == null ||
        next == null ||
        state.phase != RestPhase.running ||
        (next.after != previous.after && next.after != null)) {
      return null;
    }
    final moved = total + next.endsAt.difference(previous.endsAt).inSeconds;
    return moved > 0 ? moved : null;
  }

  /// A rest button on the lock screen, pressed maybe before the app ran:
  /// applied once the workout is loaded, and handled once the rest
  /// notification follows the moved rest, as the app may be put back to
  /// sleep as soon as the press is handled.
  Future<void> _onRestPress(LockScreenRestPress press) async {
    try {
      if (_workout.state.status == WorkoutStatus.loading) {
        await _workout.stream.firstWhere(
          (state) => state.status != WorkoutStatus.loading,
        );
      }
      if (isClosed) return;
      switch (press.action) {
        case LockScreenRestAction.shorten:
          _workout.shortenRest();
        case LockScreenRestAction.extend:
          _workout.extendRest();
        case LockScreenRestAction.skip:
          _workout.skipRest();
      }
      // The moved rest reaches [_onWorkout] after this turn.
      await Future<void>.delayed(Duration.zero);
      await _notificationCalls;
    } finally {
      press.handled();
    }
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
    final settings = _settings.state.settings;
    final text = _lockScreenText(
      active,
      nextSet(workout, _lastTicked ?? rest?.after),
      settings.weightUnit,
    );
    final resting =
        rest != null && rest.runsAt(_clock()) && settings.restTimer.enabled;
    // Before its first tick a rest is whole: it starts now.
    final total = _restTotalS;
    return LockScreenWorkout(
      name: workout.name,
      startedAt: workout.startedAt,
      current: text.current,
      set: text.set,
      rest: resting
          ? RestCountdown(
              startsAt: total == null
                  ? _clock()
                  : rest.endsAt.subtract(Duration(seconds: total)),
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
    // Sets added, removed or moved (a warm-up goes before the working
    // sets): its place may now name another done set.
    if (!sameShape(before, now)) {
      _lastTicked = null;
      return;
    }
    final ticked = newlyDone(before, now);
    if (ticked != null) {
      _lastTicked = ticked;
      return;
    }
    // An edit may have unticked it: keep it only while it is done.
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
    _settleNotification();
  }

  /// The app is in front again.
  void shown() {
    _hidden = false;
    _settleNotification();
    if (_lockScreenFailing) _lockScreenKnown = false;
    _tick();
  }

  /// Whether to ask, as a workout starts, to notify when a rest is over:
  /// the rest timer is on and this device has not been asked (see
  /// [ShouldAskRestNotifications]). Answer with [answerNotify].
  Future<bool> shouldAskNotify() async {
    final rest = _settings.state.settings.restTimer;
    return rest.enabled && await _shouldAsk(rest.notify);
  }

  /// The user's answer to [shouldAskNotify]. "Not now" is remembered on
  /// this device only, so other devices still ask; a yes is the user's, on
  /// every device.
  Future<void> answerNotify({required bool allow}) async {
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

  /// Schedules the notification for the end of the running rest while
  /// the app is hidden and the user wants it, else cancels it, after the
  /// calls before.
  void _settleNotification() {
    _notificationCalls = _notificationCalls
        .then((_) => _applyNotification())
        .onError<Object>(
          (error, stack) =>
              Log.e('rest', 'rest notification not settled', error, stack),
        );
  }

  Future<void> _applyNotification() async {
    final rest = _rest;
    final workout = _workout.state.workout;
    final settings = _settings.state.settings.restTimer;
    if (isClosed ||
        !_hidden ||
        rest == null ||
        workout == null ||
        !rest.runsAt(_clock()) ||
        settings.notify != true) {
      if (!_mayBePending) return;
      _mayBePending = false;
      _scheduled = null;
      final result = await _cancel(const NoParams());
      if (result.failureOrNull case final failure?) {
        _mayBePending = true;
        Log.e('rest', 'rest notification not cancelled: ${failure.message}');
      }
      return;
    }
    final text = _text(workout, nextSet(workout, rest.after));
    final notice = (
      at: rest.endsAt,
      title: text.title,
      body: text.body,
      alert: settings.alert,
    );
    if (notice == _scheduled) return;
    // Replaces the one pending: cancelling it first could leave none if
    // the app is suspended in between, as after a lock-screen press.
    _mayBePending = true;
    final result = await _schedule(notice);
    if (result.failureOrNull case final failure?) {
      _scheduled = null;
      Log.e('rest', 'rest notification not scheduled: ${failure.message}');
      return;
    }
    _scheduled = notice;
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    await _subscription.cancel();
    await _settingsSubscription.cancel();
    await _restActions.cancel();
    return super.close();
  }
}
