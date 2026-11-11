import 'package:forge_core/forge_core.dart';

import 'user_profile.dart';

abstract interface class ProfileRepository {
  /// Emits the profile of user [uid] (empty when nothing is stored), and
  /// again on every change. Errors arrive as [Failure]s.
  Stream<UserProfile> watchProfile(String uid);

  /// Stores only [fields] of [profile]; a field [profile] leaves unanswered
  /// is removed. Every other stored value is kept.
  Future<Result<void>> saveFields(
    String uid,
    UserProfile profile,
    Set<ProfileField> fields,
  );

  /// Stores every answer [answers] gives and marks onboarding completed.
  /// Stored answers it leaves unanswered are kept.
  Future<Result<void>> completeOnboarding(String uid, UserProfile answers);
}
