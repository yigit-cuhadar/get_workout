import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
  tearDown(dispatcher.clearLocalesTestValue);

  test('automatic leaves the choice to the phone; a chosen one is set', () {
    expect(appLocale(AppLanguage.automatic), isNull);
    expect(appLocale(AppLanguage.english), const Locale('en'));
    expect(appLocale(AppLanguage.turkish), const Locale('tr'));
  });

  test('automatic is the phone\'s first language the app has', () {
    dispatcher.localesTestValue = const [
      Locale('de', 'DE'),
      Locale('tr', 'TR'),
      Locale('en', 'US'),
    ];
    expect(devicePickedLocale(), const Locale('tr'));
    expect(localizationsIn(AppLanguage.automatic).localeName, 'tr');
    expect(localizationsIn(AppLanguage.english).localeName, 'en');
  });

  test('a phone in none of the app\'s languages gets English', () {
    dispatcher.localesTestValue = const [Locale('de', 'DE')];
    expect(devicePickedLocale(), const Locale('en'));
    expect(localizationsIn(AppLanguage.automatic).localeName, 'en');
    expect(localizationsIn(AppLanguage.turkish).localeName, 'tr');
  });

  test('each language is named in itself; automatic as the one it gives', () {
    for (final picked in [const Locale('en'), const Locale('tr')]) {
      expect(languageOwnName(AppLanguage.english, picked), 'English');
      expect(languageOwnName(AppLanguage.turkish, picked), 'Türkçe');
    }
    expect(
      languageOwnName(AppLanguage.automatic, const Locale('tr')),
      'Türkçe',
    );
    expect(
      languageOwnName(AppLanguage.automatic, const Locale('en')),
      'English',
    );
  });
}
