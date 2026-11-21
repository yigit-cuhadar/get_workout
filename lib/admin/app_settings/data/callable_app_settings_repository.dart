import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/app_settings.dart';
import '../domain/app_settings_repository.dart';

/// [AppSettingsRepository] on the callables `appSettingsGet`,
/// `appSettingsPublish` and `appSettingsHistory`
/// (`functions/src/app_settings`), which read and write Remote Config
/// with the Admin SDK.
class CallableAppSettingsRepository implements AppSettingsRepository {
  const CallableAppSettingsRepository(this._functions);

  final FirebaseFunctions _functions;

  static const getFunction = 'appSettingsGet';
  static const publishFunction = 'appSettingsPublish';
  static const historyFunction = 'appSettingsHistory';

  /// `details.reason` values of the functions' refusals.
  static const _notAdmin = 'not-admin';
  static const _invalidInput = 'invalid-input';
  static const _stale = 'stale';
  static const _locked = 'locked';

  @override
  Future<Result<AppSettings>> load() => guard(() async {
    final data = _map(await _call(getFunction));
    final keys = _map(data['keys']);
    return AppSettings(
      etag: '${data['etag']}',
      version: _version(_map(data['version'])),
      settings: {
        for (final MapEntry(:key, :value) in keys.entries)
          '$key': _setting(_map(value)),
      },
    );
  }, mapper: _mapError);

  @override
  Future<Result<ConfigVersion>> publish(SettingsPublish request) =>
      guard(() async {
        final data = await _call(publishFunction, {
          'etag': request.etag,
          'changes': {
            for (final change in request.changes)
              change.key: switch (change.after) {
                SetValue(:final value) => value,
                _ => null,
              },
          },
          'restoring': request.restoring,
        });
        return _version(_map(data));
      }, mapper: _mapError);

  @override
  Future<Result<List<VersionEntry>>> history() => guard(() async {
    final data = await _call(historyFunction);
    if (data is! List) throw UnknownFailure('unexpected result: $data');
    return [
      for (final item in data)
        if (_map(item) case final entry)
          VersionEntry(
            version: _version(entry),
            changed: [for (final key in entry['changed'] as List) '$key'],
            conditionsChanged: entry['conditionsChanged'] == true,
            values: {
              for (final MapEntry(:key, :value) in _map(
                entry['values'],
              ).entries)
                '$key': _value(_map(value)),
            },
          ),
    ];
  }, mapper: _mapError);

  Future<Object?> _call(String name, [Object? data]) async =>
      (await _functions.httpsCallable(name).call<Object?>(data)).data;

  static Map<Object?, Object?> _map(Object? value) =>
      value is Map ? value : throw UnknownFailure('unexpected result: $value');

  static RemoteSetting _setting(Map<Object?, Object?> data) => RemoteSetting(
    value: _value(_map(data['current'])),
    conditional: [
      for (final item in data['conditional'] as List)
        if (_map(item) case final entry)
          ConditionalValue(
            '${entry['condition']}',
            _value(_map(entry['setting'])),
          ),
    ],
  );

  static SettingValue _value(Map<Object?, Object?> data) =>
      switch (data['kind']) {
        'value' => SetValue('${data['value'] ?? ''}'),
        'inAppDefault' => const AppDefault(),
        final kind => ConsoleValue('$kind', '${data['id'] ?? ''}'),
      };

  static ConfigVersion _version(Map<Object?, Object?> data) => ConfigVersion(
    number: (data['number'] as num?)?.toInt() ?? 0,
    updatedAt: switch (data['updatedAtMillis']) {
      final num millis => DateTime.fromMillisecondsSinceEpoch(millis.toInt()),
      _ => null,
    },
    by: data['by'] as String?,
    origin: switch (data['origin']) {
      'panel' => PublishOrigin.panel,
      'console' => PublishOrigin.console,
      _ => PublishOrigin.other,
    },
    restoredFrom: (data['restoredFrom'] as num?)?.toInt(),
  );

  static Failure? _mapError(Object error) {
    if (error is! FirebaseFunctionsException) return mapFirebaseError(error);
    final message = error.message ?? error.code;
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    return switch ((error.code, reason)) {
      (_, _notAdmin) => PermissionFailure(message, error),
      (_, _stale) => AppSettingsStaleFailure(message, error),
      (_, _locked) => SettingLockedFailure(message, error),
      (_, _invalidInput) => ValidationFailure(message),
      // Not deployed (404), or deployed without permission to call it.
      ('not-found' || 'permission-denied', _) => AppSettingsUnavailableFailure(
        message,
        error,
      ),
      _ => mapFirebaseError(error),
    };
  }
}
