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
    );
  }

  static Map<String, Object?> _toMap(UserSettings settings) => {
    'weightUnit': _weightCodes[settings.weightUnit],
    'lengthUnit': _lengthCodes[settings.lengthUnit],
    'themeMode': _themeCodes[settings.themePreference],
  };

  /// Unknown or missing codes fall back, so a newer app version's values never
  /// break an older one.
  static T _decode<T>(Map<T, String> codes, Object? code, T fallback) {
    for (final MapEntry(:key, :value) in codes.entries) {
      if (value == code) return key;
    }
    return fallback;
  }
}
