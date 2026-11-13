import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../../body/domain/body_entry.dart';
import '../../programs/domain/calendar_date.dart';
import '../domain/settings_repository.dart';
import '../domain/user_settings.dart';

/// Settings live in the `settings` map of `users/{uid}`, a document shared
/// with other features, so writes always merge. `FirestoreCollection` only
/// offers whole-document writes, hence the direct Firestore access.
class FirestoreSettingsRepository implements SettingsRepository {
  const FirestoreSettingsRepository(this._firestore, {required this.defaults});

  final FirebaseFirestore _firestore;

  /// Used for whatever the document does not store (yet).
  final UserSettings defaults;

  static const _weightCodes = {WeightUnit.kg: 'kg', WeightUnit.lb: 'lb'};
  static const _lengthCodes = {LengthUnit.cm: 'cm', LengthUnit.inch: 'in'};
  static const _themeCodes = {
    ThemePreference.system: 'system',
    ThemePreference.light: 'light',
    ThemePreference.dark: 'dark',
  };
  static const _effortCodes = {
    EffortScale.byFeel: 'feel',
    EffortScale.rir: 'rir',
    EffortScale.rpe: 'rpe',
  };

  /// [WeekStart.automatic] is stored as no value.
  static const _weekStartCodes = {
    WeekStart.monday: 'monday',
    WeekStart.sunday: 'sunday',
    WeekStart.saturday: 'saturday',
  };
  static const _schemeCodes = {
    WarmupScheme.off: 'off',
    WarmupScheme.light: 'light',
    WarmupScheme.standard: 'standard',
    WarmupScheme.full: 'full',
    WarmupScheme.custom: 'custom',
  };
  static const _scopeCodes = {
    WarmupScope.every: 'every',
    WarmupScope.firstPerMuscle: 'firstPerMuscle',
  };
  static const _tipCodes = {
    Tip.effort: 'effort',
    Tip.setTypes: 'setTypes',
    Tip.autoWarmups: 'autoWarmups',
  };

  @override
  Stream<UserSettings> watchSettings(String uid) =>
      _user(uid)
          .snapshots()
          .map((snap) => _fromMap(snap.data()?['settings']))
          .transform(
            StreamTransformer.fromHandlers(
              handleError: (error, stack, sink) {
                final failure =
                    mapFirebaseError(error) ?? UnknownFailure('$error', error);
                Log.e('settings', failure.message, error, stack);
                sink.addError(failure, stack);
              },
            ),
          );

  @override
  Future<Result<void>> saveSettings(String uid, UserSettings settings) => guard(
    () =>
        _user(uid).set({'settings': _toMap(settings)}, SetOptions(merge: true)),
    mapper: mapFirebaseError,
  );

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _firestore.collection('users').doc(uid);

  UserSettings _fromMap(Object? raw) {
    final map = raw is Map ? raw : const <String, Object?>{};
    return UserSettings(
      weightUnit: _decode(_weightCodes, map['weightUnit'], defaults.weightUnit),
      lengthUnit: _decode(_lengthCodes, map['lengthUnit'], defaults.lengthUnit),
      themePreference: _decode(
        _themeCodes,
        map['themeMode'],
        defaults.themePreference,
      ),
      // "Off" was an older choice, replaced by by feel.
      effortScale: map['effortScale'] == 'off'
          ? EffortScale.byFeel
          : _decode(_effortCodes, map['effortScale'], defaults.effortScale),
      weekStart: _decode(_weekStartCodes, map['weekStart'], defaults.weekStart),
      restTimer: _restTimer(map['restTimer']),
      warmups: _warmups(map['warmups'], map['autoWarmups']),
      seenTips: _tips(map['seenTips']),
      stepGoal: _stepGoal(map['stepGoal']),
      workoutReminder: _workoutReminder(map['reminders']),
      measurementReminder: _measurementReminder(map['reminders']),
      customBarWeightKg: _barWeight(map['barWeightKg']),
      customPlates: _plates(map['plates']),
      customTrackedMeasurements: _measurements(map['trackedMeasurements']),
    );
  }

  /// The week start, bar, plates and tracked measurements are written only
  /// while chosen or customised; deleting them returns the user to the
  /// default. Seen tips are only ever added, by [markTipSeen].
  @override
  Future<Result<void>> markTipSeen(String uid, Tip tip) => guard(
    () => _user(uid).set({
      'settings': {
        'seenTips': FieldValue.arrayUnion([_tipCodes[tip]]),
      },
    }, SetOptions(merge: true)),
    mapper: mapFirebaseError,
  );

  static Map<String, Object?> _toMap(UserSettings settings) => {
    'weightUnit': _weightCodes[settings.weightUnit],
    'lengthUnit': _lengthCodes[settings.lengthUnit],
    'themeMode': _themeCodes[settings.themePreference],
    'effortScale': _effortCodes[settings.effortScale],
    'weekStart': _weekStartCodes[settings.weekStart] ?? FieldValue.delete(),
    'restTimer': {
      'enabled': settings.restTimer.enabled,
      'defaultS': settings.restTimer.defaultS,
      'notify': ?settings.restTimer.notify,
    },
    'warmups': {
      'scheme': _schemeCodes[settings.warmups.scheme],
      'custom': [
        for (final step in settings.warmups.custom)
          {'percent': step.percent, 'reps': step.reps},
      ],
      'scope': _scopeCodes[settings.warmups.scope],
    },
    // What app versions before the schemes read.
    'autoWarmups': settings.warmups.scheme != WarmupScheme.off,
    'stepGoal': settings.stepGoal,
    'reminders': {
      'workout': {
        'enabled': settings.workoutReminder.enabled,
        'minute': settings.workoutReminder.minute,
      },
      'measurement': {
        'enabled': settings.measurementReminder.enabled,
        'everyWeeks': settings.measurementReminder.everyWeeks,
        'from': ?settings.measurementReminder.from?.toIso(),
        'minute': settings.measurementReminder.minute,
      },
    },
    'barWeightKg': settings.customBarWeightKg ?? FieldValue.delete(),
    'plates':
        settings.customPlates
            ?.map((plate) => {'weightKg': plate.weightKg, 'pairs': plate.pairs})
            .toList() ??
        FieldValue.delete(),
    'trackedMeasurements':
        settings.customTrackedMeasurements
            ?.map((measurement) => measurement.code)
            .toList() ??
        FieldValue.delete(),
  };

  /// Unknown codes are dropped; anything but a list reads as not chosen.
  static Set<BodyMeasurement>? _measurements(Object? raw) => raw is List
      ? {for (final code in raw) ?BodyMeasurement.fromCode(code)}
      : null;

  /// The warm-up settings; without them (written before schemes), the old
  /// switch [legacy]: off reads as off, on or missing as the defaults.
  /// Malformed custom sets are dropped and values clamped; a custom scheme
  /// left without sets reads as standard.
  WarmupSettings _warmups(Object? raw, Object? legacy) {
    final fallback = defaults.warmups;
    if (raw is! Map) {
      return legacy == false
          ? fallback.copyWith(scheme: WarmupScheme.off)
          : fallback;
    }
    final custom = [
      if (raw['custom'] case final List<Object?> entries)
        for (final entry in entries)
          if (entry case {'percent': final num percent, 'reps': final num reps}
              when percent.isFinite && reps.isFinite)
            WarmupStep(
              percent.round().clamp(
                WarmupLimits.minPercent,
                WarmupLimits.maxPercent,
              ),
              reps.round().clamp(WarmupLimits.minReps, WarmupLimits.maxReps),
            ),
    ].take(WarmupLimits.maxSets).toList();
    var scheme = _decode(_schemeCodes, raw['scheme'], fallback.scheme);
    if (scheme == WarmupScheme.custom && custom.isEmpty) {
      scheme = WarmupScheme.standard;
    }
    // This app writes both in agreement: a mismatch is an older version
    // flipping the switch last, which wins.
    if (legacy == false) scheme = WarmupScheme.off;
    if (legacy == true && scheme == WarmupScheme.off) {
      scheme = WarmupScheme.standard;
    }
    return WarmupSettings(
      scheme: scheme,
      custom: custom,
      scope: _decode(_scopeCodes, raw['scope'], fallback.scope),
    );
  }

  /// Unknown codes are dropped; anything but a list reads as none seen.
  static Set<Tip> _tips(Object? raw) => raw is List
      ? {
          for (final MapEntry(:key, :value) in _tipCodes.entries)
            if (raw.contains(value)) key,
        }
      : const {};

  /// Anything missing or of the wrong type reads as the default; the
  /// duration is clamped to the limits.
  RestTimerSettings _restTimer(Object? raw) {
    final fallback = defaults.restTimer;
    if (raw is! Map) return fallback;
    final enabled = raw['enabled'];
    final seconds = raw['defaultS'];
    final notify = raw['notify'];
    return RestTimerSettings(
      enabled: enabled is bool ? enabled : fallback.enabled,
      defaultS: seconds is num && seconds.isFinite
          ? seconds.round().clamp(
              RestTimerSettings.minS,
              RestTimerSettings.maxS,
            )
          : fallback.defaultS,
      notify: notify is bool ? notify : fallback.notify,
    );
  }

  /// Anything but a number reads as the default; a number is rounded and
  /// clamped to the limits.
  int _stepGoal(Object? raw) => raw is num && raw.isFinite
      ? raw.round().clamp(StepGoal.min, StepGoal.max)
      : defaults.stepGoal;

  /// Anything missing or of the wrong type reads as the default.
  WorkoutReminderSettings _workoutReminder(Object? reminders) {
    final fallback = defaults.workoutReminder;
    final raw = reminders is Map ? reminders['workout'] : null;
    if (raw is! Map) return fallback;
    final enabled = raw['enabled'];
    return WorkoutReminderSettings(
      enabled: enabled is bool ? enabled : fallback.enabled,
      minute: _minute(raw['minute']) ?? fallback.minute,
    );
  }

  /// Anything missing or of the wrong type reads as the default; a cadence
  /// the app does not offer reads as the nearest longer one.
  MeasurementReminderSettings _measurementReminder(Object? reminders) {
    final fallback = defaults.measurementReminder;
    final raw = reminders is Map ? reminders['measurement'] : null;
    if (raw is! Map) return fallback;
    final enabled = raw['enabled'];
    final weeks = raw['everyWeeks'];
    return MeasurementReminderSettings(
      enabled: enabled is bool ? enabled : fallback.enabled,
      everyWeeks: weeks is num && weeks.isFinite
          ? MeasurementReminderSettings.choicesWeeks.firstWhere(
              (choice) => choice >= weeks,
              orElse: () => MeasurementReminderSettings.choicesWeeks.last,
            )
          : fallback.everyWeeks,
      from: CalendarDate.tryParse(raw['from']) ?? fallback.from,
      minute: _minute(raw['minute']) ?? fallback.minute,
    );
  }

  static int? _minute(Object? raw) => raw is num && raw.isFinite
      ? raw.round().clamp(0, ReminderTime.max)
      : null;

  static double? _barWeight(Object? raw) =>
      raw is num ? raw.toDouble().clamp(0, maxBarWeightKg) : null;

  /// Malformed entries are dropped and values outside the limits clamped,
  /// rather than failing the whole settings.
  static List<Plate>? _plates(Object? raw) {
    if (raw is! List) return null;
    final plates = [
      for (final entry in raw)
        if (entry case {'weightKg': final num weight, 'pairs': final int pairs}
            when weight > 0)
          Plate(
            weightKg: weight.toDouble().clamp(
              minPlateWeightKg,
              maxPlateWeightKg,
            ),
            pairs: pairs.clamp(0, maxPlatePairs),
          ),
    ]..sort((a, b) => b.weightKg.compareTo(a.weightKg));
    return plates.take(maxPlateSizes).toList();
  }

  /// Unknown or missing codes fall back, so a newer app version's values never
  /// break an older one.
  static T _decode<T>(Map<T, String> codes, Object? code, T fallback) {
    for (final MapEntry(:key, :value) in codes.entries) {
      if (value == code) return key;
    }
    return fallback;
  }
}
