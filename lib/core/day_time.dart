import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../features/settings/presentation/first_weekday.dart';
import '../features/settings/presentation/settings_cubit.dart';
import '../l10n/app_localizations.dart';

/// "Today, 08:10", else the day and the time, "Tue, Nov 10, 07:45", with
/// the year when it is not [now]'s.
String dayTimeText(BuildContext context, DateTime date, {DateTime? now}) {
  final l10n = AppLocalizations.of(context);
  final local = date.toLocal();
  final today = now ?? DateTime.now();
  final time = MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(local));
  if (DateUtils.isSameDay(local, today)) return l10n.dayTimeToday(time);
  final day = local.year == today.year
      ? DateFormat.MMMEd(l10n.localeName)
      : DateFormat.yMMMEd(l10n.localeName);
  return l10n.dayTime(day.format(local), time);
}

/// Asks for a day up to today in the Forge date picker, starting on
/// [initial]'s; null when cancelled. Needs [SettingsCubit] above.
Future<DateTime?> pickPastDay(BuildContext context, DateTime initial) {
  final words = MaterialLocalizations.of(context);
  final firstWeekday = currentFirstWeekday(context.read<SettingsCubit>());
  final narrow = words.narrowWeekdays;
  final now = DateTime.now();
  return showForgeDatePicker(
    context: context,
    picker: ForgeDatePicker(
      title: words.datePickerHelpText,
      initial: initial.isAfter(now) ? now : initial,
      lastDate: now,
      firstWeekday: firstWeekday,
      // Sunday first; ISO 7 is Sunday.
      weekdays: [for (var i = 0; i < 7; i++) narrow[(firstWeekday + i) % 7]],
      okLabel: words.okButtonLabel,
      cancelLabel: words.cancelButtonLabel,
    ),
  );
}
