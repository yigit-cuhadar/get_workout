import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise_usecases.dart';
import 'profile_repository.dart';
import 'user_profile.dart';

typedef ProfileFieldsUpdate = ({
  String uid,
  UserProfile profile,
  Set<ProfileField> fields,
});

typedef OnboardingAnswers = ({String uid, UserProfile answers});

class WatchProfile {
  const WatchProfile(this._repository);
  final ProfileRepository _repository;

  Stream<UserProfile> call(String uid) => _repository.watchProfile(uid);
}

/// Stores the chosen answers. The equipment belongs to the exercise library,
/// so it is saved through the library's own use case, the one writer of
/// `profile.equipment`.
class UpdateProfile implements UseCase<void, ProfileFieldsUpdate> {
  const UpdateProfile(this._repository, this._saveEquipment);
  final ProfileRepository _repository;
  final SaveOwnedEquipment _saveEquipment;

  @override
  Future<Result<void>> call(ProfileFieldsUpdate params) {
    final (:uid, :profile, :fields) = params;
    final others = {...fields}..remove(ProfileField.equipment);
    return _all([
      if (fields.contains(ProfileField.equipment))
        if (profile.equipment case final owned?)
          _saveEquipment((uid: uid, equipment: owned)),
      if (others.isNotEmpty) _repository.saveFields(uid, profile, others),
    ]);
  }
}

/// Stores the answers given, the equipment through the library as in
/// [UpdateProfile], and marks onboarding completed.
class CompleteOnboarding implements UseCase<void, OnboardingAnswers> {
  const CompleteOnboarding(this._repository, this._saveEquipment);
  final ProfileRepository _repository;
  final SaveOwnedEquipment _saveEquipment;

  @override
  Future<Result<void>> call(OnboardingAnswers params) {
    final (:uid, :answers) = params;
    return _all([
      if (answers.equipment case final owned?)
        _saveEquipment((uid: uid, equipment: owned)),
      _repository.completeOnboarding(uid, answers),
    ]);
  }
}

/// Starts every write at once: offline, Firestore completes none of them
/// until the server answers, so waiting for one before the next would hold
/// the rest back. The first failure, if any, is the result.
Future<Result<void>> _all(List<Future<Result<void>>> writes) async {
  for (final result in await Future.wait(writes)) {
    if (!result.isOk) return result;
  }
  return const Ok(null);
}
