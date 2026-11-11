import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../settings/presentation/settings_cubit.dart';
import '../domain/rest.dart';
import '../domain/rest_usecases.dart';
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
  final ShouldAskRestNotifications _shouldAsk;
  final AllowRestNotifications _allow;
  final DeclineRestNotifications _decline;
  final ScheduleRestNotification _schedule;
  final CancelRestNotification _cancel;
  final RestNotificationText _text;
  final DateTime Function() _clock;
  late final StreamSubscription<ActiveWorkoutState> _subscription;
  late WorkoutStatus _status;
  Rest? _rest;
  Timer? _timer;
  bool _hidden = false;

  /// Bumped whenever a scheduled notification may no longer be wanted: the
  /// rest changed or the app showed.
  int _generation = 0;

  /// Whether asking was considered in this run of the app.
  bool _considered = false;

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
    return granted.valueOrNull ?? false;
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
    return super.close();
  }
}
