import 'package:forge_core/forge_core.dart';

import 'settings_repository.dart';
import 'user_settings.dart';

typedef SettingsUpdate = ({String uid, UserSettings settings});

class WatchSettings {
  const WatchSettings(this._repository);
  final SettingsRepository _repository;

  Stream<UserSettings> call(String uid) => _repository.watchSettings(uid);
}

class UpdateSettings implements UseCase<void, SettingsUpdate> {
  const UpdateSettings(this._repository);
  final SettingsRepository _repository;

  @override
  Future<Result<void>> call(SettingsUpdate params) =>
      _repository.saveSettings(params.uid, params.settings);
}
