import 'package:forge_core/forge_core.dart';
import 'package:intl/intl.dart';

import '../../features/exercises/domain/vocabulary.dart';

/// A stored code as a label: `front_delt` → "Front delt". The app has no
/// localized vocabulary names yet; the codes are the vocabulary.
String codeLabel(Coded value) {
  final words = value.code.replaceAll('_', ' ');
  return words[0].toUpperCase() + words.substring(1);
}

String codeLabels(Iterable<Coded> values) => values.map(codeLabel).join(', ');

final _dateTime = DateFormat('yyyy-MM-dd HH:mm');

String dateTimeLabel(DateTime? value) =>
    value == null ? 'pending' : _dateTime.format(value.toLocal());

/// What the panel says about a failed load or save.
String failureMessage(Failure failure) => switch (failure) {
  PermissionFailure() =>
    'You are not allowed to edit: the admin claim is missing or expired. '
        'Refresh access on the sign-in screen, or sign out and in again.',
  NetworkFailure() => 'No connection to Firebase. Try again.',
  NotFoundFailure() => 'This exercise does not exist.',
  AuthFailure(:final code) => switch (code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'Wrong email or password.',
    'too-many-requests' => 'Too many attempts. Try again later.',
    'invalid-email' => 'That email address is not valid.',
    _ => 'Sign-in failed: ${failure.message}',
  },
  _ => 'Something went wrong: ${failure.message}',
};
