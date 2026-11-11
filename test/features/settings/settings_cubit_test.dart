import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/settings/domain/settings_repository.dart';
import 'package:get_workout/features/settings/domain/settings_usecases.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  const defaults = UserSettings(
    weightUnit: WeightUnit.kg,
    lengthUnit: LengthUnit.cm,
  );
  final pounds = defaults.copyWith(weightUnit: WeightUnit.lb);
  final dark = defaults.copyWith(themePreference: ThemePreference.dark);
  const guest = AuthUser(id: 'g1', isAnonymous: true);
  const member = AuthUser(id: 'u1', email: 'a@b.co');

  late MockAuthRepository auth;
  late MockSettingsRepository settings;
  late StreamController<AuthUser?> users;
  late Map<String, StreamController<UserSettings>> stored;

  setUpAll(() => registerFallbackValue(defaults));

  setUp(() {
    auth = MockAuthRepository();
    settings = MockSettingsRepository();
    users = StreamController<AuthUser?>();
    stored = {};
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => settings.watchSettings(any())).thenAnswer(
      (call) => stored
          .putIfAbsent(
            call.positionalArguments.first as String,
            StreamController<UserSettings>.new,
          )
          .stream,
    );
  });

  SettingsCubit build() => SettingsCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchSettings: WatchSettings(settings),
    updateSettings: UpdateSettings(settings),
    defaults: defaults,
  );

  test('starts with the defaults', () {
    expect(build().state, const SettingsState(defaults));
  });

  blocTest<SettingsCubit, SettingsState>(
    'follows the settings of whoever is signed in',
    build: build,
    act: (_) async {
      users.add(guest);
      await pumpEventQueue();
      stored['g1']!.add(pounds);
      await pumpEventQueue();
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add(dark);
      await pumpEventQueue();
      // The previous user's stream is no longer followed.
      stored['g1']!.add(defaults);
    },
    expect: () => [SettingsState(pounds), SettingsState(dark)],
    verify: (_) => expect(stored['g1']!.hasListener, isFalse),
  );

  blocTest<SettingsCubit, SettingsState>(
    'a profile change of the same user keeps the subscription',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      users.add(const AuthUser(id: 'u1', email: 'a@b.co', displayName: 'A'));
    },
    verify: (_) => verify(() => settings.watchSettings('u1')).called(1),
  );

  blocTest<SettingsCubit, SettingsState>(
    'update saves for the current user',
    setUp: () =>
        when(() => settings.saveSettings(any(), any()))
            .thenAnswer((_) async => const Ok(null)),
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      await cubit.update(dark);
    },
    expect: () => const <SettingsState>[],
    verify: (_) => verify(() => settings.saveSettings('u1', dark)).called(1),
  );

  const failure = NetworkFailure();

  blocTest<SettingsCubit, SettingsState>(
    'a failed update keeps the previous settings and reports the failure',
    setUp: () =>
        when(() => settings.saveSettings(any(), any()))
            .thenAnswer((_) async => const Err(failure)),
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add(pounds);
      await pumpEventQueue();
      await cubit.update(dark);
    },
    expect: () => [
      SettingsState(pounds),
      SettingsState(pounds, failure: failure),
    ],
  );

  blocTest<SettingsCubit, SettingsState>(
    'a stream error keeps the last settings',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!
        ..add(pounds)
        ..addError(const PermissionFailure());
    },
    expect: () => [SettingsState(pounds)],
  );

  blocTest<SettingsCubit, SettingsState>(
    'update without a user saves nothing',
    build: build,
    act: (cubit) => cubit.update(dark),
    expect: () => const <SettingsState>[],
    verify: (_) => verifyNever(() => settings.saveSettings(any(), any())),
  );
}
