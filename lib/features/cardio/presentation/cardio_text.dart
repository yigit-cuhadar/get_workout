import 'package:material_ui/material_ui.dart';

import '../../../core/number_text.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/cardio_session.dart';
import '../domain/cardio_type.dart';
import '../domain/cardio_validation.dart';

/// The health store the device reads from, by name.
String healthStoreName(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return Theme.of(context).platform == TargetPlatform.iOS
      ? l10n.stepsStoreApple
      : l10n.stepsStoreGoogle;
}

/// Health Connect names a session's source by package name only; the
/// apps known here are named, any other reads as the store.
const _healthConnectSources = {
  'com.strava': 'Strava',
  'com.google.android.apps.fitness': 'Google Fit',
  'com.sec.android.app.shealth': 'Samsung Health',
  'com.garmin.android.apps.connectmobile': 'Garmin Connect',
  'com.fitbit.FitbitMobile': 'Fitbit',
  'com.nike.plusgps': 'Nike Run Club',
  'com.runtastic.android': 'adidas Running',
  'fi.polar.polarflow': 'Polar Flow',
  'com.huawei.health': 'Huawei Health',
  'com.mi.health': 'Mi Fitness',
  'com.withings.wiscale2': 'Withings',
  'com.suunto.android': 'Suunto',
};

/// The tag of a session read from the health store: the store on iOS,
/// the app that saved it on Android when known, else the store.
String healthSourceName(BuildContext context, CardioSession session) {
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return healthStoreName(context);
  }
  return _healthConnectSources[session.healthSource] ??
      healthStoreName(context);
}

/// Distances follow the user's length unit: km with cm, miles with inches.
DistanceUnit distanceUnitFor(LengthUnit unit) => switch (unit) {
  LengthUnit.cm => DistanceUnit.km,
  LengthUnit.inch => DistanceUnit.mile,
};

/// `h:mm:ss`, or `m:ss` under an hour.
String formatDuration(Duration duration) {
  final seconds = duration.inSeconds;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// A pace to the nearest second, as [formatDuration] writes it.
String formatPace(Duration pace) =>
    formatDuration(Duration(seconds: (pace.inMilliseconds / 1000).round()));

extension CardioText on AppLocalizations {
  String distanceUnitLabel(DistanceUnit unit) => switch (unit) {
    DistanceUnit.km => cardioUnitKm,
    DistanceUnit.mile => cardioUnitMi,
  };

  String distanceText(double km, DistanceUnit unit) {
    final value = formatDecimal(unit.fromKm(km), 2);
    return switch (unit) {
      DistanceUnit.km => cardioDistanceKm(value),
      DistanceUnit.mile => cardioDistanceMi(value),
    };
  }

  /// Pace or speed as the session's type shows it; null when it has none.
  String? rateText(CardioSession session, DistanceUnit unit) {
    switch (session.type.rate) {
      case CardioRate.pace:
        final pace = session.pace(unit);
        if (pace == null) return null;
        final text = formatPace(pace);
        return switch (unit) {
          DistanceUnit.km => cardioPacePerKm(text),
          DistanceUnit.mile => cardioPacePerMi(text),
        };
      case CardioRate.speed:
        final speed = session.speed(unit);
        if (speed == null) return null;
        final text = formatDecimal(speed, 1);
        return switch (unit) {
          DistanceUnit.km => cardioSpeedKmh(text),
          DistanceUnit.mile => cardioSpeedMph(text),
        };
      case CardioRate.none:
        return null;
    }
  }

  String cardioMinutesOf(Duration duration) =>
      cardioMinutes((duration.inSeconds / 60).round());

  String issueText(CardioIssue issue) => switch (issue) {
    CardioIssue.durationMissing => cardioErrorDuration,
    CardioIssue.durationTooLong => cardioErrorDurationTooLong,
    CardioIssue.dateInFuture => cardioErrorDateInFuture,
    CardioIssue.distanceOutOfRange => cardioErrorDistance,
    CardioIssue.caloriesOutOfRange => cardioErrorCalories,
    CardioIssue.heartRateOutOfRange => cardioErrorHeartRate,
    CardioIssue.inclineOutOfRange => cardioErrorIncline,
    CardioIssue.noteTooLong => cardioErrorNote,
  };

  String typeName(CardioType type) => switch (type) {
    CardioType.treadmillRun => cardioTypeTreadmillRun,
    CardioType.treadmillWalk => cardioTypeTreadmillWalk,
    CardioType.outdoorRun => cardioTypeOutdoorRun,
    CardioType.outdoorWalk => cardioTypeOutdoorWalk,
    CardioType.hiking => cardioTypeHiking,
    CardioType.stationaryBike => cardioTypeStationaryBike,
    CardioType.outdoorCycle => cardioTypeOutdoorCycle,
    CardioType.elliptical => cardioTypeElliptical,
    CardioType.rowing => cardioTypeRowing,
    CardioType.stairClimber => cardioTypeStairClimber,
    CardioType.swimming => cardioTypeSwimming,
    CardioType.jumpRope => cardioTypeJumpRope,
    CardioType.hiit => cardioTypeHiit,
    CardioType.other => cardioTypeOther,
  };
}
