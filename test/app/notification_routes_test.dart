import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/features/notifications/data/notification_taps.dart';

void main() {
  test('the start is the splash, retry, onboarding and its suggestion', () {
    for (final location in [
      '',
      Routes.splash,
      Routes.startFailed,
      Routes.onboarding,
      Routes.onboardingSignIn,
      Routes.afterOnboarding,
    ]) {
      expect(isPastStart(location), isFalse, reason: location);
    }
    for (final location in [
      Routes.today,
      Routes.profile,
      Routes.workout,
      Routes.history,
    ]) {
      expect(isPastStart(location), isTrue, reason: location);
    }
  });

  test('reminders and announcements lead to their tabs', () {
    expect(
      notificationDestination(NotificationTarget.workout, Routes.profile),
      Routes.today,
    );
    expect(
      notificationDestination(NotificationTarget.announcement, Routes.steps),
      Routes.today,
    );
    expect(
      notificationDestination(NotificationTarget.measurement, Routes.today),
      Routes.bodyMeasureNew,
    );
  });

  test('a measurement reminder opens a new measurement day, unless one is '
      'open', () {
    expect(
      notificationDestination(NotificationTarget.measurement, Routes.body),
      Routes.bodyMeasureNew,
    );
    expect(
      notificationDestination(
        NotificationTarget.measurement,
        Routes.bodyMeasureNew,
      ),
      isNull,
    );
  });

  test('a workout reminder leaves the workout in progress in front', () {
    expect(
      notificationDestination(NotificationTarget.workout, Routes.workout),
      isNull,
    );
    expect(
      notificationDestination(
        NotificationTarget.workout,
        Routes.workoutPicker(max: 1, multiple: false).split('?').first,
      ),
      isNull,
    );
  });
}
