import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../core/widgets/app_mark.dart';
import '../l10n/app_localizations.dart';

/// The start screen while the session and the profile resolve: the
/// launch logo alone on its light ground, as the native launch screen
/// draws it; the slow-start line after 2 s.
class AppSplash extends StatelessWidget {
  const AppSplash({super.key});

  static const slowAfter = Duration(seconds: 2);
  static const _markSize = 22.0;
  static const _logo = Image(
    image: AssetImage('assets/images/splash_logo.png'),
  );

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    return Scaffold(
      backgroundColor: colors.onFeatured,
      body: SplashScreen(
        mark: const AppMark(size: _markSize),
        name: AppLocalizations.of(context).appTitle,
        background: colors.onFeatured,
        foreground: colors.featured,
        slowAfter: slowAfter,
        logo: _logo,
      ),
    );
  }
}

/// The start screen when the guest session could not start, with [onRetry].
class AppStartFailed extends StatelessWidget {
  const AppStartFailed({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ForgeStyle.of(context).colors;
    return Scaffold(
      backgroundColor: colors.onFeatured,
      body: SplashScreen.failed(
        mark: const AppMark(size: AppSplash._markSize),
        name: l10n.appTitle,
        background: colors.onFeatured,
        foreground: colors.featured,
        logo: AppSplash._logo,
        message: l10n.appStartFailed,
        retryLabel: l10n.retry,
        onRetry: onRetry,
      ),
    );
  }
}
