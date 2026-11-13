import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/presentation/first_weekday.dart';

void main() {
  test('follows the region, whatever the app language', () {
    expect(localeFirstWeekday(const Locale('tr', 'TR')), DateTime.monday);
    expect(localeFirstWeekday(const Locale('en', 'GB')), DateTime.monday);
    expect(localeFirstWeekday(const Locale('de', 'DE')), DateTime.monday);
    expect(localeFirstWeekday(const Locale('en', 'US')), DateTime.sunday);
  });

  test('a locale intl lacks falls back to its language', () {
    expect(localeFirstWeekday(const Locale('ar', 'SA')), DateTime.saturday);
    expect(localeFirstWeekday(const Locale('fa', 'IR')), DateTime.saturday);
    expect(localeFirstWeekday(const Locale('tr')), DateTime.monday);
    // English in a region intl has no English locale for.
    expect(localeFirstWeekday(const Locale('en', 'TR')), DateTime.sunday);
  });

  test('an unknown language falls back to Monday', () {
    expect(localeFirstWeekday(const Locale('xx', 'YY')), DateTime.monday);
    expect(localeFirstWeekday(const Locale('und')), DateTime.monday);
  });
}
