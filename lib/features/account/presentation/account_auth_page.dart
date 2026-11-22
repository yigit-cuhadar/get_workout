import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../app/legal_links.dart';
import '../../../core/open_link.dart';
import '../../../core/widgets/app_mark.dart';
import '../../../l10n/app_localizations.dart';
import 'auth_strings.dart';

/// The sign-in providers offered next to email: Apple first on iOS, where
/// the App Store requires it beside Google; Android offers Google alone
/// (Apple there would need a Services ID).
List<SocialProvider> get socialProviders => [
  if (defaultTargetPlatform == TargetPlatform.iOS) SocialProvider.apple,
  SocialProvider.google,
];

/// forge_auth's sign-in page with GetWorkout's mark, name, tagline, text
/// and legal links; [initialSignUp] opens the email form's create mode.
class AccountAuthPage extends StatelessWidget {
  const AccountAuthPage({
    super.key,
    required this.initialSignUp,
    required this.onSignedIn,
  });

  final bool initialSignUp;
  final VoidCallback onSignedIn;

  Future<void> _open(BuildContext context, Uri uri) async {
    final failed = AppLocalizations.of(context).linkOpenFailed;
    if (await openLink(uri)) return;
    if (context.mounted) {
      showForgeSnackbar(context, message: failed, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthPage(
      mark: const AppMark(),
      name: l10n.appTitle,
      tagline: l10n.authTagline,
      onTerms: () => _open(context, LegalLinks.terms),
      onPrivacy: () => _open(context, LegalLinks.privacy),
      strings: localizedAuthStrings(l10n),
      providers: socialProviders,
      initialSignUp: initialSignUp,
      onSignedIn: onSignedIn,
    );
  }
}
