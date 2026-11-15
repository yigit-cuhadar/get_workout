import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../settings/presentation/settings_cubit.dart';
import 'active_workout_cubit.dart';

/// Keeps the screen awake while a workout is in progress, if the user's
/// settings want it, and lets it sleep again once the workout ends or the
/// setting is turned off. Needs [ActiveWorkoutCubit] and [SettingsCubit]
/// above it.
class KeepScreenOn extends StatelessWidget {
  const KeepScreenOn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final on =
        context.select((ActiveWorkoutCubit cubit) => cubit.state.inProgress) &&
        context.select(
          (SettingsCubit cubit) => cubit.state.settings.keepScreenOn,
        );
    return _Wakelock(on: on, child: child);
  }
}

class _Wakelock extends StatefulWidget {
  const _Wakelock({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  State<_Wakelock> createState() => _WakelockState();
}

class _WakelockState extends State<_Wakelock> {
  @override
  void initState() {
    super.initState();
    if (widget.on) _apply(true);
  }

  @override
  void didUpdateWidget(_Wakelock old) {
    super.didUpdateWidget(old);
    if (old.on != widget.on) _apply(widget.on);
  }

  void _apply(bool on) => unawaited(
    WakelockPlus.toggle(enable: on).catchError((Object error) {
      Log.e('workout', 'screen lock not changed', error);
    }),
  );

  @override
  Widget build(BuildContext context) => widget.child;
}
