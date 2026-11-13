import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/first_weekday.dart';

void main() {
  test('follows the region, whatever the language', () {
    expect(localeFirstWeekday(const Locale('en', 'TR')), DateTime.monday);
    expect(localeFirstWeekday(const Locale('tr', 'TR')), DateTime.monday);
    expect(localeFirstWeekday(const Locale('en', 'GB')), DateTime.monday);
    expect(localeFirstWeekday(const Locale('en', 'US')), DateTime.sunday);
    expect(localeFirstWeekday(const Locale('ar', 'EG')), DateTime.saturday);
    expect(localeFirstWeekday(const Locale('dv', 'MV')), DateTime.friday);
  });

  test('a region CLDR does not list starts on Monday', () {
    expect(localeFirstWeekday(const Locale('xx', 'YY')), DateTime.monday);
    expect(regionFirstWeekday('de'), DateTime.monday);
    expect(regionFirstWeekday('sa'), DateTime.sunday);
  });

  test('without a region, the language decides, else Monday', () {
    expect(localeFirstWeekday(const Locale('en')), DateTime.sunday);
    expect(localeFirstWeekday(const Locale('tr')), DateTime.monday);
    expect(localeFirstWeekday(const Locale('fa')), DateTime.saturday);
    expect(localeFirstWeekday(const Locale('xx')), DateTime.monday);
  });

  test('automatic takes even a Friday start', () {
    expect(WeekStart.automatic.firstWeekday(DateTime.friday), DateTime.friday);
  });
}
