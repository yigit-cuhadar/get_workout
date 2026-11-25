import 'package:forge_core/forge_core.dart';
import 'package:forge_live_activity/forge_live_activity.dart';

import '../domain/workout_lock_screen.dart';

/// [WorkoutLockScreen] on iOS: one Live Activity for the whole workout
/// through forge_live_activity, drawn by the `RestTimer` widget extension,
/// which reads this content as `WorkoutActivityContent`. It shows the
/// workout, or the rest while one runs; a rest's end is its stale date,
/// from which it shows the workout again by itself, so a rest that ends
/// while the app is suspended needs no update. Below iOS 16.2 nothing
/// shows and nothing fails; with Live Activities turned off, or while the
/// app may not start one (not active), a show fails, so it is tried again.
/// During a rest it has −15 s, +15 s and Skip (iOS 17+), labelled with
/// [restButtons], which work without opening the app: the Runner moves the
/// rest shown at once (`AppDelegate.swift`) and the package hands the
/// press to [restActions], keeping it until taken when the app does not
/// run.
class IosWorkoutLockScreen implements WorkoutLockScreen {
  const IosWorkoutLockScreen({
    required this.restButtons,
    this._activity = const LiveActivity(),
  });

  final ({String shorten, String extend, String skip}) Function() restButtons;
  final LiveActivity _activity;

  @override
  Future<Result<void>> show(LockScreenWorkout workout) {
    final set = workout.set;
    final rest = workout.rest;
    final buttons = rest == null ? null : restButtons();
    return _activity.show({
      'name': workout.name,
      'startedAt': workout.startedAt.millisecondsSinceEpoch,
      'set': set == null
          ? null
          : {
              'exercise': set.exercise,
              'position': set.position,
              'line': set.line,
              'done': set.done,
            },
      'rest': rest == null || buttons == null
          ? null
          : {
              'startsAt': rest.startsAt.millisecondsSinceEpoch,
              'endsAt': rest.endsAt.millisecondsSinceEpoch,
              'title': rest.title,
              'detail': rest.detail,
              'shorten': buttons.shorten,
              'extend': buttons.extend,
              'skip': buttons.skip,
            },
    }, staleAt: rest?.endsAt);
  }

  @override
  Future<Result<void>> clear() => _activity.end();

  @override
  Stream<void> taps() => _activity.taps();

  /// The buttons' actions are [LockScreenRestAction]'s names
  /// (`RestAction` in `WorkoutActivityIntents.swift`).
  @override
  Stream<LockScreenRestPress> restActions() =>
      _activity.presses().expand((press) {
        final action = LockScreenRestAction.values.asNameMap()[press.action];
        if (action == null) {
          press.handled();
          return const [];
        }
        return [LockScreenRestPress(action, onHandled: press.handled)];
      });
}
