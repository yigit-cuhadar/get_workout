import 'package:bloc_test/bloc_test.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_app_gate/forge_app_gate.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/access/domain/access_usecases.dart';
import 'package:get_workout/admin/app_settings/data/callable_app_settings_repository.dart';
import 'package:get_workout/admin/app_settings/domain/app_settings.dart';
import 'package:get_workout/admin/app_settings/domain/app_settings_repository.dart';
import 'package:get_workout/admin/app_settings/domain/app_settings_usecases.dart';
import 'package:get_workout/admin/app_settings/presentation/app_settings_cubit.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:mocktail/mocktail.dart';

class MockRepository extends Mock implements AppSettingsRepository {}

class MockCheckAdminAccess extends Mock implements CheckAdminAccess {}

class MockFunctions extends Mock implements FirebaseFunctions {}

class MockCallable extends Mock implements HttpsCallable {}

class MockCallableResult extends Mock implements HttpsCallableResult<Object?> {}

class FunctionsError extends FirebaseFunctionsException {
  FunctionsError(String code, {String? reason})
    : super(
        code: code,
        message: 'error',
        details: reason == null ? null : {'reason': reason},
      );
}

const _version14 = ConfigVersion(
  number: 14,
  by: 'admin@example.com',
  origin: PublishOrigin.panel,
);

AppSettings _settings({
  String etag = 'etag-14',
  ConfigVersion version = _version14,
  Map<String, RemoteSetting> overrides = const {},
}) => AppSettings(
  etag: etag,
  version: version,
  settings: {
    'paywall_layout': const RemoteSetting(
      value: SetValue('a'),
      conditional: [ConditionalValue('paywall_test_b', SetValue('b'))],
    ),
    'maintenance': const RemoteSetting(value: AppDefault()),
    'min_version_ios': const RemoteSetting(value: SetValue('1.0.0')),
    ...overrides,
  },
);

void main() {
  setUpAll(() {
    registerFallbackValue(const NoParams());
    registerFallbackValue(const SettingsPublish(etag: '', changes: []));
  });

  group('settingSpecs', () {
    test("are the app's Remote Config keys with its defaults", () {
      final appDefaults = {
        ...SubscriptionModule.remoteConfigDefaults,
        ...AppGateModule.remoteConfigDefaults,
      };
      expect(
        {for (final spec in settingSpecs) spec.key: spec.appDefault},
        {
          for (final MapEntry(:key, :value) in appDefaults.entries)
            key: '$value',
        },
      );
    });

    test('check each kind of value', () {
      expect(specOf('paywall_layout').problem('c'), isNull);
      expect(specOf('paywall_layout').problem('d'), isNotNull);
      expect(specOf('maintenance').problem('true'), isNull);
      expect(specOf('maintenance').problem('yes'), isNotNull);
      expect(specOf('min_version_ios').problem(''), isNull);
      expect(specOf('min_version_ios').problem('1.2.10'), isNull);
      expect(specOf('min_version_ios').problem('v1.2'), isNotNull);
      expect(specOf('min_version_ios').problem('1.2.'), isNotNull);
      expect(specOf('maintenance_message').problem('x' * 300), isNull);
      expect(specOf('maintenance_message').problem('x' * 301), isNotNull);
    });
  });

  group('restoreChanges', () {
    test('lists the defaults that differ, leaving console-owned ones', () {
      final current = _settings(
        overrides: {
          'recommended_version_ios': const RemoteSetting(
            value: ConsoleValue('rollout', 'r1'),
          ),
        },
      );
      const entry = VersionEntry(
        version: ConfigVersion(number: 12),
        changed: [],
        conditionsChanged: false,
        values: {
          'paywall_layout': SetValue('a'),
          'maintenance': SetValue('true'),
          'min_version_ios': AppDefault(),
          'recommended_version_ios': SetValue('1.0.0'),
        },
      );
      expect(restoreChanges(current, entry), const [
        SettingChange(
          'maintenance',
          before: AppDefault(),
          after: SetValue('true'),
        ),
        SettingChange(
          'min_version_ios',
          before: SetValue('1.0.0'),
          after: AppDefault(),
        ),
      ]);
    });
  });

  group('PublishAppSettings', () {
    late MockRepository repository;

    setUp(() {
      repository = MockRepository();
      when(() => repository.publish(any()))
          .thenAnswer((_) async => const Ok(ConfigVersion(number: 15)));
    });

    test('refuses no changes and broken values without asking', () async {
      final publish = PublishAppSettings(repository);
      expect(
        (await publish(const SettingsPublish(etag: 'e', changes: [])))
            .failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await publish(
          const SettingsPublish(
            etag: 'e',
            changes: [
              SettingChange(
                'min_version_ios',
                before: AppDefault(),
                after: SetValue('soon'),
              ),
            ],
          ),
        )).failureOrNull,
        isA<ValidationFailure>(),
      );
      verifyNever(() => repository.publish(any()));
    });

    test('publishes valid changes', () async {
      const request = SettingsPublish(
        etag: 'e',
        changes: [
          SettingChange(
            'min_version_ios',
            before: AppDefault(),
            after: SetValue('1.1.0'),
          ),
          SettingChange(
            'maintenance',
            before: SetValue('true'),
            after: AppDefault(),
          ),
        ],
      );
      final result = await PublishAppSettings(repository)(request);
      expect(result.valueOrNull?.number, 15);
      verify(() => repository.publish(request)).called(1);
    });
  });

  group('CallableAppSettingsRepository', () {
    late MockFunctions functions;
    late MockCallable callable;
    late MockCallableResult result;
    late CallableAppSettingsRepository repository;

    setUp(() {
      functions = MockFunctions();
      callable = MockCallable();
      result = MockCallableResult();
      repository = CallableAppSettingsRepository(functions);
      when(() => functions.httpsCallable(any())).thenReturn(callable);
      when(() => callable.call<Object?>(any())).thenAnswer((_) async => result);
    });

    test('load reads the version and every key', () async {
      when(() => result.data).thenReturn({
        'etag': 'etag-14',
        'version': {
          'number': 14,
          'updatedAtMillis': 1000,
          'by': 'admin@example.com',
          'origin': 'panel',
          'restoredFrom': null,
        },
        'keys': {
          'paywall_layout': {
            'current': {'kind': 'value', 'value': 'a'},
            'conditional': [
              {
                'condition': 'paywall_test_b',
                'setting': {'kind': 'experiment', 'id': '7'},
              },
            ],
          },
          'maintenance': {
            'current': {'kind': 'inAppDefault'},
            'conditional': <Object?>[],
          },
        },
      });
      final loaded = await repository.load();
      verify(() => functions.httpsCallable('appSettingsGet')).called(1);
      expect(
        loaded.valueOrNull,
        AppSettings(
          etag: 'etag-14',
          version: ConfigVersion(
            number: 14,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
            by: 'admin@example.com',
            origin: PublishOrigin.panel,
          ),
          settings: const {
            'paywall_layout': RemoteSetting(
              value: SetValue('a'),
              conditional: [
                ConditionalValue(
                  'paywall_test_b',
                  ConsoleValue('experiment', '7'),
                ),
              ],
            ),
            'maintenance': RemoteSetting(value: AppDefault()),
          },
        ),
      );
    });

    test('publish sends new values, null for the app default', () async {
      when(() => result.data)
          .thenReturn({'number': 15, 'origin': 'panel', 'restoredFrom': 12});
      final published = await repository.publish(
        const SettingsPublish(
          etag: 'etag-14',
          restoring: 12,
          changes: [
            SettingChange(
              'maintenance',
              before: SetValue('true'),
              after: AppDefault(),
            ),
            SettingChange(
              'min_version_ios',
              before: AppDefault(),
              after: SetValue('1.1.0'),
            ),
          ],
        ),
      );
      expect(published.valueOrNull?.restoredFrom, 12);
      verify(() => functions.httpsCallable('appSettingsPublish')).called(1);
      verify(
        () => callable.call<Object?>({
          'etag': 'etag-14',
          'changes': {'maintenance': null, 'min_version_ios': '1.1.0'},
          'restoring': 12,
        }),
      ).called(1);
    });

    test('history reads each version with its values', () async {
      when(() => result.data).thenReturn([
        {
          'number': 12,
          'updatedAtMillis': null,
          'by': 'owner@example.com',
          'origin': 'console',
          'restoredFrom': null,
          'changed': ['paywall_layout'],
          'conditionsChanged': true,
          'values': {
            'paywall_layout': {'kind': 'value', 'value': 'b'},
          },
        },
      ]);
      expect((await repository.history()).valueOrNull, const [
        VersionEntry(
          version: ConfigVersion(
            number: 12,
            by: 'owner@example.com',
            origin: PublishOrigin.console,
          ),
          changed: ['paywall_layout'],
          conditionsChanged: true,
          values: {'paywall_layout': SetValue('b')},
        ),
      ]);
    });

    test('maps refusals to failures', () async {
      Future<Failure?> failureFor(FunctionsError error) async {
        when(() => callable.call<Object?>(any())).thenThrow(error);
        return (await repository.load()).failureOrNull;
      }

      expect(
        await failureFor(
          FunctionsError('permission-denied', reason: 'not-admin'),
        ),
        isA<PermissionFailure>(),
      );
      expect(
        await failureFor(
          FunctionsError('failed-precondition', reason: 'stale'),
        ),
        isA<AppSettingsStaleFailure>(),
      );
      expect(
        await failureFor(
          FunctionsError('failed-precondition', reason: 'locked'),
        ),
        isA<SettingLockedFailure>(),
      );
      expect(
        await failureFor(
          FunctionsError('invalid-argument', reason: 'invalid-input'),
        ),
        isA<ValidationFailure>(),
      );
      expect(
        await failureFor(FunctionsError('not-found')),
        isA<AppSettingsUnavailableFailure>(),
      );
    });
  });

  group('AppSettingsCubit', () {
    late MockRepository repository;
    late MockCheckAdminAccess checkAdminAccess;

    AppSettingsCubit build() => AppSettingsCubit(
      loadAppSettings: LoadAppSettings(repository),
      loadSettingsHistory: LoadSettingsHistory(repository),
      publishAppSettings: PublishAppSettings(repository),
      checkAdminAccess: checkAdminAccess,
    );

    setUp(() {
      repository = MockRepository();
      checkAdminAccess = MockCheckAdminAccess();
      when(() => repository.load()).thenAnswer((_) async => Ok(_settings()));
    });

    Future<AppSettingsCubit> loaded() async {
      final cubit = build();
      await cubit.load();
      return cubit;
    }

    test('an edit back to the current value is no change', () async {
      final cubit = await loaded();
      cubit.edit('min_version_ios', '1.1.0');
      expect(cubit.state.changes, const [
        SettingChange(
          'min_version_ios',
          before: SetValue('1.0.0'),
          after: SetValue('1.1.0'),
        ),
      ]);
      expect(cubit.state.canPublish, isTrue);
      cubit.edit('min_version_ios', '1.0.0');
      expect(cubit.state.edits, isEmpty);
      // The app's default counts as the current value.
      cubit.edit('maintenance', 'false');
      expect(cubit.state.edits, isEmpty);
    });

    test('a broken value blocks publishing', () async {
      final cubit = await loaded();
      cubit.edit('min_version_ios', '1.x');
      expect(cubit.state.problemOf('min_version_ios'), isNotNull);
      expect(cubit.state.canPublish, isFalse);
    });

    test('a key the console owns cannot be edited', () async {
      when(() => repository.load()).thenAnswer(
        (_) async => Ok(
          _settings(
            overrides: {
              'paywall_layout': const RemoteSetting(
                value: ConsoleValue('experiment', '7'),
              ),
            },
          ),
        ),
      );
      final cubit = await loaded();
      cubit.edit('paywall_layout', 'c');
      expect(cubit.state.edits, isEmpty);
    });

    test('discard drops the edits and rebuilds the fields', () async {
      final cubit = await loaded();
      final formVersion = cubit.state.formVersion;
      cubit
        ..edit('min_version_ios', '1.1.0')
        ..discard();
      expect(cubit.state.edits, isEmpty);
      expect(cubit.state.formVersion, formVersion + 1);
    });

    test(
      'a publish sends the edits onto the loaded etag, then reloads',
      () async {
        final cubit = await loaded();
        when(() => repository.publish(any()))
            .thenAnswer((_) async => const Ok(ConfigVersion(number: 15)));
        when(() => repository.load()).thenAnswer(
          (_) async => Ok(
            _settings(
              etag: 'etag-15',
              overrides: {
                'min_version_ios': const RemoteSetting(
                  value: SetValue('1.1.0'),
                ),
              },
            ),
          ),
        );
        cubit.edit('min_version_ios', '1.1.0');
        await cubit.publish(cubit.state.changes);
        verify(
          () => repository.publish(
            const SettingsPublish(
              etag: 'etag-14',
              changes: [
                SettingChange(
                  'min_version_ios',
                  before: SetValue('1.0.0'),
                  after: SetValue('1.1.0'),
                ),
              ],
            ),
          ),
        ).called(1);
        expect(cubit.state.publishStatus, PublishStatus.published);
        expect(cubit.state.published?.number, 15);
        expect(cubit.state.settings?.etag, 'etag-15');
        expect(cubit.state.edits, isEmpty);
      },
    );

    test('a stale publish keeps the edits; a reload keeps them too', () async {
      final cubit = await loaded();
      when(() => repository.publish(any()))
          .thenAnswer((_) async => const Err(AppSettingsStaleFailure()));
      cubit.edit('min_version_ios', '1.1.0');
      await cubit.publish(cubit.state.changes);
      expect(cubit.state.publishStatus, PublishStatus.failed);
      expect(cubit.state.publishFailure, isA<AppSettingsStaleFailure>());
      expect(cubit.state.edits, {'min_version_ios': '1.1.0'});
      when(() => repository.load())
          .thenAnswer((_) async => Ok(_settings(etag: 'etag-15')));
      await cubit.load();
      expect(cubit.state.settings?.etag, 'etag-15');
      expect(cubit.state.edits, {'min_version_ios': '1.1.0'});
    });

    blocTest<AppSettingsCubit, AppSettingsState>(
      'a publish refused for the claim refreshes the token to tell',
      build: build,
      seed: () => AppSettingsState(settings: _settings()),
      setUp: () {
        when(() => repository.publish(any()))
            .thenAnswer((_) async => const Err(PermissionFailure()));
        when(() => checkAdminAccess(true))
            .thenAnswer((_) async => const Ok(true));
      },
      act: (cubit) => cubit.publish(const [
        SettingChange(
          'maintenance',
          before: AppDefault(),
          after: SetValue('true'),
        ),
      ]),
      verify: (cubit) {
        expect(cubit.state.publishFailure, isA<PermissionFailure>());
        expect(cubit.state.accessRefreshed, isTrue);
      },
    );

    test('the history loads once, and a restore names its version', () async {
      const entry = VersionEntry(
        version: ConfigVersion(number: 12),
        changed: ['maintenance'],
        conditionsChanged: false,
        values: {'maintenance': SetValue('true')},
      );
      when(() => repository.history())
          .thenAnswer((_) async => const Ok([entry]));
      when(() => repository.publish(any()))
          .thenAnswer((_) async => const Ok(ConfigVersion(number: 15)));
      final cubit = await loaded();
      await cubit.openHistory();
      cubit.closeHistory();
      await cubit.openHistory();
      verify(() => repository.history()).called(1);
      expect(cubit.state.history, [entry]);

      cubit.openVersion(12);
      final changes = restoreChanges(cubit.state.settings!, entry);
      await cubit.publish(changes, restoring: 12);
      verify(
        () => repository.publish(
          SettingsPublish(etag: 'etag-14', changes: changes, restoring: 12),
        ),
      ).called(1);
      // Reloaded after the publish, since it is open.
      verify(() => repository.history()).called(1);
      expect(cubit.state.openedVersion, isNull);
    });

    test('a failed load says why and Retry loads again', () async {
      when(() => repository.load())
          .thenAnswer((_) async => const Err(AppSettingsUnavailableFailure()));
      final cubit = await loaded();
      expect(cubit.state.settings, isNull);
      expect(cubit.state.loadFailure, isA<AppSettingsUnavailableFailure>());
      when(() => repository.load()).thenAnswer((_) async => Ok(_settings()));
      await cubit.load();
      expect(cubit.state.loadFailure, isNull);
      expect(cubit.state.settings, isNotNull);
    });
  });
}
