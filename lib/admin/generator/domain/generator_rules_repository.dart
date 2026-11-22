import 'package:forge_core/forge_core.dart';

import 'generator_rules.dart';

/// The generator's rules, through the admin-only callables of
/// `functions/src/generator`. Every call fails with [PermissionFailure]
/// without the admin claim, [GeneratorRulesUnavailableFailure] when the
/// functions cannot be called and [NetworkFailure] offline.
abstract interface class GeneratorRulesRepository {
  /// The current rules (version 0 when none were published), or [version]
  /// of them; [NotFoundFailure] when there is no such version.
  Future<Result<StoredRules>> load({int? version});

  /// The server's validator and, when it finds nothing, the standard
  /// answers run through [rules].
  Future<Result<RulesCheck>> check(GeneratorRules rules);

  /// Publishes [request]; the new version. Fails with
  /// [GeneratorRulesStaleFailure] when the current version is no longer
  /// [RulesPublish.base], [GeneratorRulesInvalidFailure] with the
  /// validator's problems and [ValidationFailure] for another refused value.
  Future<Result<int>> publish(RulesPublish request);

  /// The latest versions, newest first, without their rules.
  Future<Result<List<StoredRules>>> history();
}
