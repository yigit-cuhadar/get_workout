import 'package:forge_core/forge_core.dart';

import 'app_settings.dart';
import 'app_settings_repository.dart';

class LoadAppSettings implements UseCase<AppSettings, NoParams> {
  const LoadAppSettings(this._repository);
  final AppSettingsRepository _repository;

  @override
  Future<Result<AppSettings>> call(NoParams params) => _repository.load();
}

class LoadSettingsHistory implements UseCase<List<VersionEntry>, NoParams> {
  const LoadSettingsHistory(this._repository);
  final AppSettingsRepository _repository;

  @override
  Future<Result<List<VersionEntry>>> call(NoParams params) =>
      _repository.history();
}

/// Publishes the changes, or fails with a [ValidationFailure] without
/// asking the server when there are none or a new value breaks its key's
/// rule ([SettingSpec.problem]).
class PublishAppSettings implements UseCase<ConfigVersion, SettingsPublish> {
  const PublishAppSettings(this._repository);
  final AppSettingsRepository _repository;

  @override
  Future<Result<ConfigVersion>> call(SettingsPublish params) async {
    if (params.changes.isEmpty) {
      return const Err(ValidationFailure('Nothing to publish.'));
    }
    final problems = [
      for (final change in params.changes)
        if (change.after case SetValue(:final value))
          if (specOf(change.key).problem(value) case final problem?)
            '${change.key}: $problem',
    ];
    if (problems.isNotEmpty) return Err(ValidationFailure(problems.join(' ')));
    return _repository.publish(params);
  }
}
