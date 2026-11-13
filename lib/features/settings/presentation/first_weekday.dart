import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'settings_cubit.dart';

/// The first day of the week of [locale] as an ISO weekday (1 Monday to 7
/// Sunday), from intl's date symbols: the full locale's, else its
/// language's, else Monday. Not the app's language: English is its only
/// one, while a phone set to Turkey or the UK starts weeks on Monday.
int localeFirstWeekday(Locale locale) {
  final country = locale.countryCode;
  final first =
      (country == null
          ? null
          : _firstDays['${locale.languageCode}_$country']) ??
      _firstDays[locale.languageCode] ??
      0;
  // intl counts from 0, Monday.
  return first + 1;
}

/// Each locale intl has symbols for, with its first day of the week; built
/// once, synchronously, from the symbols bundled with intl.
final Map<String, int> _firstDays = {
  for (final MapEntry(:key, :value) in dateTimeSymbolMap().entries)
    key: value.FIRSTDAYOFWEEK,
};

/// The phone's first day of the week, read outside any widget (cubits shared
/// by the whole app); widgets use [BuildContext.watchFirstWeekday].
int deviceFirstWeekday() =>
    localeFirstWeekday(WidgetsBinding.instance.platformDispatcher.locale);

/// The first day of the week the whole app uses as [settings] stand now,
/// for cubits made without a context; they follow changes through
/// [FirstWeekdayListener].
int currentFirstWeekday(SettingsCubit settings) =>
    settings.state.settings.weekStart.firstWeekday(deviceFirstWeekday());

/// Gives the widgets below the phone's first day of the week, following
/// changes of the phone's language and region.
class DeviceFirstWeekday extends StatefulWidget {
  const DeviceFirstWeekday({super.key, required this.child});

  final Widget child;

  @override
  State<DeviceFirstWeekday> createState() => _DeviceFirstWeekdayState();
}

class _DeviceFirstWeekdayState extends State<DeviceFirstWeekday>
    with WidgetsBindingObserver {
  int _firstWeekday = deviceFirstWeekday();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeLocales(List<Locale>? locales) =>
      setState(() => _firstWeekday = deviceFirstWeekday());

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _DeviceFirstWeekdayScope(_firstWeekday, child: widget.child);
}

class _DeviceFirstWeekdayScope extends InheritedWidget {
  const _DeviceFirstWeekdayScope(this.firstWeekday, {required super.child});

  final int firstWeekday;

  @override
  bool updateShouldNotify(_DeviceFirstWeekdayScope old) =>
      firstWeekday != old.firstWeekday;
}

extension FirstWeekdayContext on BuildContext {
  /// The phone's first day of the week (see [localeFirstWeekday]). Only in
  /// `build`; outside [DeviceFirstWeekday] (tests) it is read once.
  int watchDeviceFirstWeekday() =>
      dependOnInheritedWidgetOfExactType<_DeviceFirstWeekdayScope>()
          ?.firstWeekday ??
      deviceFirstWeekday();

  /// The first day of the week the whole app uses, as an ISO weekday: the
  /// user's setting, else the phone's. Only in `build`, which it makes run
  /// again when it changes; cubits are given it at creation and follow
  /// changes through [FirstWeekdayListener].
  int watchFirstWeekday() =>
      select((SettingsCubit cubit) => cubit.state.settings.weekStart)
          .firstWeekday(watchDeviceFirstWeekday());
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

  /// The first weekday the cubits use as this is shown.
  final int created;
  final void Function(BuildContext context, int firstWeekday) onChanged;
  final Widget child;

  @override
  State<FirstWeekdayListener> createState() => _FirstWeekdayListenerState();
}

class _FirstWeekdayListenerState extends State<FirstWeekdayListener> {
  late int _reported = widget.created;

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
