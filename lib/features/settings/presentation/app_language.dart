import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/user_settings.dart';
import 'settings_cubit.dart';

/// The locale `MaterialApp` is given for [language]; null when automatic,
/// so it picks from the phone's languages itself.
Locale? appLocale(AppLanguage language) => switch (language.code) {
  final code? => Locale(code),
  null => null,
};

/// The app's language when automatic: the phone's first language the app
/// has, else English, the way `MaterialApp` picks it.
Locale devicePickedLocale() => basicLocaleListResolution(
  WidgetsBinding.instance.platformDispatcher.locales,
  AppLocalizations.supportedLocales,
);

/// The app's strings in [language], for text made outside any widget
/// (notifications); widgets use `AppLocalizations.of`.
AppLocalizations localizationsIn(AppLanguage language) =>
    lookupAppLocalizations(appLocale(language) ?? devicePickedLocale());

/// The app's strings in its language as [settings] stand now.
AppLocalizations currentLocalizations(SettingsCubit settings) =>
    localizationsIn(settings.state.settings.language);

/// [language]'s name in itself, never translated; for automatic, the
/// language it gives on a phone whose languages give [devicePicked].
String languageOwnName(AppLanguage language, Locale devicePicked) =>
    switch (language) {
      AppLanguage.automatic => languageOwnName(
        AppLanguage.values.firstWhere(
          (other) => other.code == devicePicked.languageCode,
          orElse: () => AppLanguage.english,
        ),
        devicePicked,
      ),
      AppLanguage.english => 'English',
      AppLanguage.turkish => 'Türkçe',
    };
