import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/subscription/domain/paywall_moment.dart';

void main() {
  group('paywallMomentDue', () {
    test('only for a known free user', () {
      for (final moment in [
        PaywallMoment.onboarding,
        PaywallMoment.workoutDone,
      ]) {
        expect(paywallMomentDue(moment, premium: false, seen: {}), isTrue);
        expect(paywallMomentDue(moment, premium: true, seen: {}), isFalse);
        expect(paywallMomentDue(moment, premium: null, seen: {}), isFalse);
        expect(paywallMomentDue(moment, premium: false, seen: null), isFalse);
      }
    });

    test('onboarding once; a workout every time', () {
      expect(
        paywallMomentDue(
          PaywallMoment.onboarding,
          premium: false,
          seen: {Tip.onboardingPaywall},
        ),
        isFalse,
      );
      expect(PaywallMoment.workoutDone.tip, isNull);
      expect(
        paywallMomentDue(
          PaywallMoment.workoutDone,
          premium: false,
          seen: {Tip.onboardingPaywall},
        ),
        isTrue,
      );
    });
  });

  test('the offering decides at onboarding and on app open only', () {
    expect(PaywallMoment.onboarding.offeringDecides, isTrue);
    expect(PaywallMoment.appOpen.offeringDecides, isTrue);
    expect(PaywallMoment.workoutDone.offeringDecides, isFalse);
    expect(PaywallMoment.appOpen.tip, isNull);
  });

  group('offeringDismissible', () {
    test('is true unless the metadata says false', () {
      expect(offeringDismissible(const {}), isTrue);
      expect(offeringDismissible(const {'dismissible': true}), isTrue);
      expect(offeringDismissible(const {'dismissible': 'true'}), isTrue);
      expect(offeringDismissible(const {'dismissible': null}), isTrue);
      expect(offeringDismissible(const {'other': false}), isTrue);
      expect(offeringDismissible(const {'dismissible': false}), isFalse);
      expect(offeringDismissible(const {'dismissible': 'false'}), isFalse);
    });
  });
}
