import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../../exercises/domain/vocabulary.dart';
import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';

/// The profile is the `profile` map of `users/{uid}`, a document shared with
/// other features; `profile.equipment` is also written by the exercise
/// library. Writes therefore merge and name only the fields they change.
/// `FirestoreCollection` only offers whole-document writes, hence the direct
/// Firestore access.
class FirestoreProfileRepository implements ProfileRepository {
  const FirestoreProfileRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const _completedAt = 'onboardingCompletedAt';

  @override
  Stream<UserProfile> watchProfile(String uid) =>
      _user(uid)
          .snapshots()
          .map((snap) => _fromMap(snap.data()?['profile']))
          .transform(
            StreamTransformer.fromHandlers(
              handleError: (error, stack, sink) {
                final failure =
                    mapFirebaseError(error) ?? UnknownFailure('$error', error);
                Log.e('profile', failure.message, error, stack);
                sink.addError(failure, stack);
              },
            ),
          );

  @override
  Future<Result<void>> saveFields(
    String uid,
    UserProfile profile,
    Set<ProfileField> fields,
  ) => _merge(uid, {
    for (final field in fields)
      _key(field): _value(profile, field) ?? FieldValue.delete(),
  });

  @override
  Future<Result<void>> completeOnboarding(String uid, UserProfile answers) =>
      _merge(uid, {
        for (final field in ProfileField.values)
          _key(field): ?_value(answers, field),
        _completedAt: FieldValue.serverTimestamp(),
      });

  /// A nested map with merge replaces only the leaves it names.
  Future<Result<void>> _merge(String uid, Map<String, Object?> profile) =>
      guard(
        () => _user(uid).set({'profile': profile}, SetOptions(merge: true)),
        mapper: mapFirebaseError,
      );

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _firestore.collection('users').doc(uid);

  static String _key(ProfileField field) => switch (field) {
    ProfileField.goal => 'goal',
    ProfileField.level => 'level',
    ProfileField.daysPerWeek => 'daysPerWeek',
    ProfileField.equipment => 'equipment',
    ProfileField.sex => 'sex',
    ProfileField.birthYear => 'birthYear',
    ProfileField.height => 'heightCm',
    ProfileField.weight => 'weightKg',
    ProfileField.targetWeight => 'targetWeightKg',
  };

  static Object? _value(UserProfile profile, ProfileField field) =>
      switch (field) {
        ProfileField.goal => profile.goal?.code,
        ProfileField.level => profile.level?.code,
        ProfileField.daysPerWeek => profile.daysPerWeek,
        // In vocabulary order, like the exercise library writes it.
        ProfileField.equipment => switch (profile.equipment) {
          final owned? => [
            for (final item in Equipment.values)
              if (owned.contains(item) && item != Equipment.bodyweight)
                item.code,
          ],
          null => null,
        },
        ProfileField.sex => profile.sex?.name,
        ProfileField.birthYear => profile.birthYear,
        ProfileField.height => profile.heightCm,
        ProfileField.weight => profile.weightKg,
        ProfileField.targetWeight => profile.targetWeightKg,
      };

  /// Malformed or unknown values (a newer app version's) read as unanswered.
  static UserProfile _fromMap(Object? raw) {
    final map = raw is Map ? raw : const <String, Object?>{};
    final equipment = map['equipment'];
    return UserProfile(
      goal: Goal.values.byCode(map['goal']),
      level: Level.values.byCode(map['level']),
      daysPerWeek: _int(map['daysPerWeek']),
      equipment: equipment is List
          ? {for (final code in equipment) ?Equipment.values.byCode(code)}
                .difference(const {Equipment.bodyweight})
          : null,
      sex: Sex.values.asNameMap()[map['sex']],
      birthYear: _int(map['birthYear']),
      heightCm: _double(map['heightCm']),
      weightKg: _double(map['weightKg']),
      targetWeightKg: _double(map['targetWeightKg']),
      onboardingCompletedAt: map.containsKey(_completedAt)
          ? _completedAtOf(map[_completedAt])
          : null,
    );
  }

  /// A server timestamp still waiting for the server reads as null; the key
  /// being there already means onboarding was completed (possibly offline),
  /// so the local time stands in until the server's arrives.
  static DateTime? _completedAtOf(Object? value) => switch (value) {
    Timestamp() => value.toDate(),
    null => DateTime.now(),
    _ => null,
  };

  static int? _int(Object? raw) => raw is num ? raw.toInt() : null;

  static double? _double(Object? raw) => raw is num ? raw.toDouble() : null;
}
