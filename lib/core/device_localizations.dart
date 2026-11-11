import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// The app's strings in the device's language, for text made outside any
/// widget (notifications), the way `MaterialApp` picks the language.
AppLocalizations deviceLocalizations() => lookupAppLocalizations(
  basicLocaleListResolution(
    WidgetsBinding.instance.platformDispatcher.locales,
    AppLocalizations.supportedLocales,
  ),
);
