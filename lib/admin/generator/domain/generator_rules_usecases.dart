import 'package:forge_core/forge_core.dart';

import 'generator_rules.dart';
import 'generator_rules_repository.dart';

/// The current rules, or the version given.
class LoadGeneratorRules implements UseCase<StoredRules, int?> {
  const LoadGeneratorRules(this._repository);
  final GeneratorRulesRepository _repository;

  @override
  Future<Result<StoredRules>> call(int? version) =>
      _repository.load(version: version);
}

class CheckGeneratorRules implements UseCase<RulesCheck, GeneratorRules> {
  const CheckGeneratorRules(this._repository);
  final GeneratorRulesRepository _repository;

  @override
  Future<Result<RulesCheck>> call(GeneratorRules rules) =>
      _repository.check(rules);
}

class PublishGeneratorRules implements UseCase<int, RulesPublish> {
  const PublishGeneratorRules(this._repository);
  final GeneratorRulesRepository _repository;

  @override
  Future<Result<int>> call(RulesPublish request) =>
      _repository.publish(request);
}

class LoadGeneratorRulesHistory
    implements UseCase<List<StoredRules>, NoParams> {
  const LoadGeneratorRulesHistory(this._repository);
  final GeneratorRulesRepository _repository;

  @override
  Future<Result<List<StoredRules>>> call(NoParams params) =>
      _repository.history();
}
