import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'settings_cubit.dart';

extension FirstWeekdayContext on BuildContext {
  /// The first day of the week the whole app uses, as an ISO weekday (1
  /// Monday to 7 Sunday): the user's setting, else the locale's. Only in
  /// `build`, which it makes run again when it changes; cubits are given it
  /// at creation and follow changes through [FirstWeekdayListener].
  int watchFirstWeekday() {
    // Material counts from 0, Sunday.
    final locale = MaterialLocalizations.of(this).firstDayOfWeekIndex;
    return select((SettingsCubit cubit) => cubit.state.settings.weekStart)
        .firstWeekday(locale == 0 ? DateTime.sunday : locale);
  }
}

/// Calls [onChanged] with [BuildContext.watchFirstWeekday] whenever it
/// differs from the one the cubits use, after the frame, so cubits never
/// emit during a build.
class FirstWeekdayListener extends StatefulWidget {
  const FirstWeekdayListener({
    super.key,
    required this.created,
    required this.onChanged,
    required this.child,
  });

  /// The first weekday the cubits were created with; null for cubits
  /// shared by the whole app, made without a context, which are then told
  /// the first one once shown.
  final int? created;
  final void Function(BuildContext context, int firstWeekday) onChanged;
  final Widget child;

  @override
  State<FirstWeekdayListener> createState() => _FirstWeekdayListenerState();
}

class _FirstWeekdayListenerState extends State<FirstWeekdayListener> {
  late int? _reported = widget.created;

  @override
  Widget build(BuildContext context) {
    final firstWeekday = context.watchFirstWeekday();
    if (firstWeekday != _reported) {
      _reported = firstWeekday;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && _reported == firstWeekday) {
          widget.onChanged(context, firstWeekday);
        }
      });
    }
    return widget.child;
  }
}
