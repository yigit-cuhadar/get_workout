import 'package:forge_core/forge_core.dart';
import 'package:intl/intl.dart';

import '../domain/admin_user.dart';

final _date = DateFormat('MMM d, yyyy');

/// A date in the admin's zone, "—" when there is none.
String userDateLabel(DateTime? value) =>
    value == null ? '—' : _date.format(value.toLocal());

/// When something ends: its date, or "never" (null).
String endLabel(DateTime? value) =>
    value == null ? 'never ends' : 'ends ${userDateLabel(value)}';

String durationLabel(PremiumDuration duration) => switch (duration) {
  PremiumDuration.week => '1 week',
  PremiumDuration.month => '1 month',
  PremiumDuration.year => '1 year',
  PremiumDuration.lifetime => 'Lifetime',
};

String providerLabel(String provider) => switch (provider) {
  'password' => 'Email and password',
  'google.com' => 'Google',
  'apple.com' => 'Apple',
  _ => provider,
};

String platformLabel(String? platform) => switch (platform) {
  'ios' => 'iOS',
  'android' => 'Android',
  null => '—',
  _ => platform,
};

String storeLabel(String store) => switch (store) {
  'app_store' => 'App Store',
  'play_store' => 'Google Play',
  'promotional' => 'Promotional',
  _ => store,
};

/// A RevenueCat code such as `in_grace_period` as words.
String codeWords(String code) {
  final words = code.replaceAll('_', ' ');
  return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

/// What the Users pages say about a failure.
String userFailureText(Failure failure) => switch (failure) {
  PermissionFailure() =>
    'This account has no current admin claim. Sign in again.',
  NetworkFailure() => 'No connection to Firebase. Try again.',
  NotFoundFailure() => 'No user has that email or user ID.',
  ValidationFailure() => 'Enter an email or a user ID.',
  OwnAccountFailure() => 'This cannot be done to your own account.',
  RevenueCatFailure(status: 403) =>
    'The RevenueCat key lacks a permission for this. Nothing changed.',
  RevenueCatFailure(:final status) =>
    'RevenueCat did not answer${status == null ? '' : ' ($status)'}. '
        'Nothing changed. Try again.',
  AuthFailure(:final code) => 'Firebase Auth refused: $code.',
  _ => 'Something went wrong: ${failure.message}',
};
