import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../l10n/app_localizations.dart';

/// The auth screens' text, taken from the app's localizations.
AuthStrings localizedAuthStrings(AppLocalizations l10n) => AuthStrings(
  signIn: l10n.authSignIn,
  signUp: l10n.authSignUp,
  email: l10n.authEmail,
  password: l10n.authPassword,
  forgotPassword: l10n.authForgotPassword,
  switchToSignUp: l10n.authSwitchToSignUp,
  switchToSignIn: l10n.authSwitchToSignIn,
  continueWithGoogle: l10n.authContinueWithGoogle,
  continueWithApple: l10n.authContinueWithApple,
  invalidEmail: l10n.authInvalidEmail,
  shortPassword: l10n.authShortPassword,
  resetSent: l10n.authResetSent,
  replaceGuestTitle: l10n.authReplaceGuestTitle,
  replaceGuestBody: l10n.authReplaceGuestBody,
  replaceGuestConfirm: l10n.authReplaceGuestConfirm,
  cancel: l10n.cancel,
  errorFor: (failure) => switch (failure) {
    NetworkFailure() => l10n.errorNetwork,
    AuthFailure(:final code) => switch (code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => l10n.authErrorWrongCredentials,
      'email-already-in-use' => l10n.authErrorEmailInUse,
      'weak-password' => l10n.authErrorWeakPassword,
      'invalid-email' => l10n.authErrorInvalidEmail,
      'too-many-requests' => l10n.authErrorTooManyRequests,
      'requires-recent-login' => l10n.authErrorRecentLogin,
      _ => l10n.authErrorSignIn,
    },
    _ => l10n.errorGeneric,
  },
);
