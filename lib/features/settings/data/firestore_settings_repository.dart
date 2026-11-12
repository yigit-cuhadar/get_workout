import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

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
    EffortScale.off: 'off',
    EffortScale.rir: 'rir',
    EffortScale.rpe: 'rpe',
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
      effortScale: _decode(
        _effortCodes,
        map['effortScale'],
        defaults.effortScale,
      ),
      restTimer: _restTimer(map['restTimer']),
      stepGoal: _stepGoal(map['stepGoal']),
      customBarWeightKg: _barWeight(map['barWeightKg']),
      customPlates: _plates(map['plates']),
    );
  }

  /// The bar and plates are written only while customised; deleting them
  /// returns the user to the standard set of their weight unit.
  static Map<String, Object?> _toMap(UserSettings settings) => {
    'weightUnit': _weightCodes[settings.weightUnit],
    'lengthUnit': _lengthCodes[settings.lengthUnit],
    'themeMode': _themeCodes[settings.themePreference],
    'effortScale': _effortCodes[settings.effortScale],
    'restTimer': {
      'enabled': settings.restTimer.enabled,
      'defaultS': settings.restTimer.defaultS,
      'notify': ?settings.restTimer.notify,
    },
    'stepGoal': settings.stepGoal,
    'barWeightKg': settings.customBarWeightKg ?? FieldValue.delete(),
    'plates':
        settings.customPlates
            ?.map((plate) => {'weightKg': plate.weightKg, 'pairs': plate.pairs})
            .toList() ??
        FieldValue.delete(),
  };

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
