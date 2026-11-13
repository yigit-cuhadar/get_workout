import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/account/presentation/consent_cubit.dart';
import 'package:get_workout/features/account/presentation/consent_prompt.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';

void main() {
  const unanswered = ConsentState(
    uid: 'a',
    stored: (consent: null, fromServer: true),
  );
  final onboarded = ProfileState(
    uid: 'a',
    status: ProfileStatus.loaded,
    profile: UserProfile(onboardingCompletedAt: DateTime(2026)),
  );

  test('asks an onboarded user the server has no answer from', () {
    expect(consentDue(unanswered, onboarded), isTrue);
  });

  test('a profile that cannot be read does not hold it back', () {
    expect(
      consentDue(
        unanswered,
        const ProfileState(uid: 'a', status: ProfileStatus.unavailable),
      ),
      isTrue,
    );
  });

  test('not while the new user\'s profile loads after a sign-out, a '
      'deletion or an account switch', () {
    expect(consentDue(unanswered, const ProfileState(uid: 'a')), isFalse);
    // The profile still shows the previous user.
    expect(
      consentDue(
        const ConsentState(uid: 'b', stored: (consent: null, fromServer: true)),
        onboarded,
      ),
      isFalse,
    );
  });

  test('not for a user on their way to onboarding', () {
    expect(
      consentDue(
        unanswered,
        const ProfileState(uid: 'a', status: ProfileStatus.loaded),
      ),
      isFalse,
    );
  });

  test('not once answered, nor from a cached copy, nor for nobody', () {
    expect(
      consentDue(
        const ConsentState(
          uid: 'a',
          stored: (consent: false, fromServer: true),
        ),
        onboarded,
      ),
      isFalse,
    );
    expect(
      consentDue(
        const ConsentState(
          uid: 'a',
          stored: (consent: null, fromServer: false),
        ),
        onboarded,
      ),
      isFalse,
    );
    expect(consentDue(const ConsentState(), const ProfileState()), isFalse);
  });
}
