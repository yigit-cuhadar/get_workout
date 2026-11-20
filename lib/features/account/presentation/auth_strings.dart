import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../l10n/app_localizations.dart';

/// The auth screens' text, taken from the app's localizations.
AuthStrings localizedAuthStrings(AppLocalizations l10n) => AuthStrings(
  signIn: l10n.authSignIn,
  signUp: l10n.authSignUp,
  signInWithEmail: l10n.authSignInWithEmail,
  email: l10n.authEmail,
  password: l10n.authPassword,
  forgotPassword: l10n.authForgotPassword,
  switchToSignUp: l10n.authSwitchToSignUp,
  switchToSignIn: l10n.authSwitchToSignIn,
  continueWithGoogle: l10n.authContinueWithGoogle,
  continueWithApple: l10n.authContinueWithApple,
  useEmail: l10n.authUseEmail,
  otherOptions: l10n.authOtherOptions,
  continueAsGuest: l10n.authContinueAsGuest,
  signingIn: l10n.authSigningIn,
  // AuthStrings puts the links where these markers stand.
  terms: l10n.authTerms('{terms}', '{privacy}'),
  termsLink: l10n.authTermsLink,
  privacyLink: l10n.authPrivacyLink,
  invalidEmail: l10n.authInvalidEmail,
  shortPassword: l10n.authShortPassword,
  resetSent: l10n.authResetSent,
  signInFailed: l10n.authSignInFailed,
  retry: l10n.retry,
  linkFailed: l10n.authLinkFailed,
  notNow: l10n.authNotNow,
  replaceGuestTitle: l10n.authReplaceGuestTitle,
  replaceGuestBody: l10n.authReplaceGuestBody,
  replaceGuestConfirm: l10n.authReplaceGuestConfirm,
  cancel: l10n.cancel,
  verifyEmailTitle: l10n.authVerifyEmailTitle,
  verifyEmailBody: l10n.authVerifyEmailBody,
  sentTo: l10n.authSentTo,
  waitingForVerification: l10n.authWaitingForVerification,
  resendEmail: l10n.authResendEmail,
  // AuthStrings puts the count where this marker stands.
  resendIn: l10n.authResendIn('{seconds}'),
  emailSent: l10n.authEmailSent,
  useAnotherAccount: l10n.authUseAnotherAccount,
  changeEmailTitle: l10n.authChangeEmailTitle,
  changeEmailBody: l10n.authChangeEmailBody,
  newEmail: l10n.authNewEmail,
  sendLink: l10n.authSendLink,
  signOutInstead: l10n.authSignOutInstead,
  verificationFailed: l10n.errorGeneric,
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
