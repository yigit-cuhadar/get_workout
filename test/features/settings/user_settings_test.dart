import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

void main() {
  const metric = UserSettings(
    weightUnit: WeightUnit.kg,
    lengthUnit: LengthUnit.cm,
  );
  const imperial = UserSettings(
    weightUnit: WeightUnit.lb,
    lengthUnit: LengthUnit.inch,
  );

  test('US, Liberia and Myanmar default to imperial', () {
    for (final country in ['US', 'LR', 'MM', 'us']) {
      expect(UserSettings.defaultsFor(country), imperial, reason: country);
    }
  });

  test('other or unknown countries default to metric', () {
    for (final country in ['GB', 'DE', 'TR', 'CA', null]) {
      expect(UserSettings.defaultsFor(country), metric, reason: '$country');
    }
  });

  test('the default theme follows the system', () {
    expect(
      UserSettings.defaultsFor('US').themePreference,
      ThemePreference.system,
    );
  });
}
