import 'package:forge_core/forge_core.dart';

import 'user_settings.dart';

abstract interface class SettingsRepository {
  /// Emits the settings of user [uid], filling anything not stored with the
  /// defaults, and again on every change. Errors arrive as [Failure]s.
  Stream<UserSettings> watchSettings(String uid);

  /// Stores [settings] without touching anything else of the user, nor the
  /// tips seen (see [markTipSeen]).
  Future<Result<void>> saveSettings(String uid, UserSettings settings);

  /// Adds [tip] to the tips user [uid] has seen, keeping every other one,
  /// also those set elsewhere meanwhile or unknown to this app version.
  Future<Result<void>> markTipSeen(String uid, Tip tip);
}
