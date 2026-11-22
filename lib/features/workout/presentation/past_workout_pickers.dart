import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/workout.dart';

/// A past workout's start: the system date picker (up to today), then the
/// time on the Forge wheel. Null when the date is not picked.
Future<DateTime?> pickWorkoutStart(
  BuildContext context,
  DateTime current,
) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: current.isAfter(now) ? now : current,
    firstDate: DateTime(2000),
    lastDate: now,
  );
  if (date == null || !context.mounted) return null;
  var time = TimeOfDay.fromDateTime(current);
  await showForgeTimeWheel(
    context: context,
    initial: time,
    onChanged: (picked) => time = picked,
  );
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// A workout's length on the Forge wheel in hours and minutes, up to the
/// longest a workout may last; [onChanged] gets each step.
Future<void> pickWorkoutDuration(
  BuildContext context,
  Duration current,
  ValueChanged<Duration> onChanged,
) {
  final l10n = AppLocalizations.of(context);
  return showForgeDurationWheel(
    context: context,
    wheel: ForgeDurationWheel.hoursMinutes(
      label: l10n.workoutDuration,
      initial: current,
      max: WorkoutLimits.maxWorkoutDuration,
      hourUnit: l10n.historyHours,
      minuteUnit: l10n.historyMinutes,
      onChanged: onChanged,
    ),
  );
}
