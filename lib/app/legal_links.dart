/// The app's legal pages, served by prod's Firebase Hosting (`legal/`).
abstract final class LegalLinks {
  static final terms = Uri.parse('https://getworkout-prod.web.app/terms');
  static final privacy = Uri.parse(privacyUrl);

  /// The one place the privacy policy's address is written: the Android
  /// build reads it from this line for `PrivacyPolicyActivity`
  /// (`android/app/build.gradle.kts`), so keep it a single-quoted literal.
  static const privacyUrl = 'https://getworkout-prod.web.app/privacy';
}
