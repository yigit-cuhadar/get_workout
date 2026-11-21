import 'package:forge_core/forge_core.dart';

import 'app_settings.dart';

/// The app's Remote Config, through the admin-only callables of
/// `functions/src/app_settings`. Every call fails with [PermissionFailure]
/// without the admin claim, [AppSettingsUnavailableFailure] when the
/// functions cannot be called and [NetworkFailure] offline.
abstract interface class AppSettingsRepository {
  Future<Result<AppSettings>> load();

  /// Publishes [request]'s new defaults as a new version; its number.
  /// Fails with [AppSettingsStaleFailure] when the template changed since
  /// [SettingsPublish.etag], [SettingLockedFailure] for a key the console
  /// owns and [ValidationFailure] when the function refuses a value.
  Future<Result<ConfigVersion>> publish(SettingsPublish request);

  /// The latest versions, newest first.
  Future<Result<List<VersionEntry>>> history();
}
