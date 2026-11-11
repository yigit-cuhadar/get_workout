import 'package:forge_core/forge_core.dart';

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

class UpdateProfile implements UseCase<void, ProfileFieldsUpdate> {
  const UpdateProfile(this._repository);
  final ProfileRepository _repository;

  @override
  Future<Result<void>> call(ProfileFieldsUpdate params) =>
      _repository.saveFields(params.uid, params.profile, params.fields);
}

class CompleteOnboarding implements UseCase<void, OnboardingAnswers> {
  const CompleteOnboarding(this._repository);
  final ProfileRepository _repository;

  @override
  Future<Result<void>> call(OnboardingAnswers params) =>
      _repository.completeOnboarding(params.uid, params.answers);
}
