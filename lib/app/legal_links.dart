/// The app's legal pages. Placeholders until the pages are published; see
/// SPEC's open questions.
abstract final class LegalLinks {
  static final terms = Uri.parse('https://example.com/getworkout/terms');
  static final privacy = Uri.parse(privacyUrl);

  /// The one place the privacy policy's address is written: the Android
  /// build reads it from this line for `PrivacyPolicyActivity`
  /// (`android/app/build.gradle.kts`), so keep it a single-quoted literal.
  static const privacyUrl = 'https://example.com/getworkout/privacy';
}
