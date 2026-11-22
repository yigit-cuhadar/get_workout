import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../domain/generator_rules.dart';
import '../domain/generator_rules_repository.dart';

/// [GeneratorRulesRepository] on the callables `generatorRulesGet`,
/// `generatorRulesCheck`, `generatorRulesPublish` and
/// `generatorRulesHistory` (`functions/src/generator/store.ts`).
class CallableGeneratorRulesRepository implements GeneratorRulesRepository {
  const CallableGeneratorRulesRepository(this._functions);

  final FirebaseFunctions _functions;

  static const getFunction = 'generatorRulesGet';
  static const checkFunction = 'generatorRulesCheck';
  static const publishFunction = 'generatorRulesPublish';
  static const historyFunction = 'generatorRulesHistory';

  /// `details.reason` values of the functions' refusals.
  static const _notAdmin = 'not-admin';
  static const _invalidInput = 'invalid-input';
  static const _stale = 'stale';

  @override
  Future<Result<StoredRules>> load({int? version}) => guard(
    () async => _stored(_map(await _call(getFunction, {'version': version}))),
    // A version the server does not have, not a missing function.
    mapper: (error) => version != null && _code(error) == 'not-found'
        ? NotFoundFailure('there is no version $version', error)
        : _mapError(error),
  );

  @override
  Future<Result<RulesCheck>> check(GeneratorRules rules) => guard(() async {
    final data = _map(await _call(checkFunction, {'rules': rules.json}));
    return RulesCheck(
      problems: [for (final problem in _list(data['problems'])) '$problem'],
      findings: [
        for (final item in _list(data['findings']))
          if (_map(item) case final finding)
            Finding(
              goal: '${finding['goal']}',
              level: '${finding['level']}',
              daysPerWeek: (finding['daysPerWeek'] as num).toInt(),
              equipment: '${finding['equipment']}',
              kind: FindingKind.values.byName('${finding['kind']}'),
              detail: '${finding['detail']}',
            ),
      ],
    );
  }, mapper: _mapError);

  @override
  Future<Result<int>> publish(RulesPublish request) => guard(() async {
    final data = _map(
      await _call(publishFunction, {
        'base': request.base,
        'rules': request.rules.json,
        'note': request.note,
        'restores': request.restores,
      }),
    );
    return (data['version'] as num).toInt();
  }, mapper: _mapError);

  @override
  Future<Result<List<StoredRules>>> history() => guard(() async {
    final data = await _call(historyFunction);
    return [for (final item in _list(data)) _stored(_map(item))];
  }, mapper: _mapError);

  Future<Object?> _call(String name, [Object? data]) async =>
      (await _functions.httpsCallable(name).call<Object?>(data)).data;

  static Map<Object?, Object?> _map(Object? value) =>
      value is Map ? value : throw UnknownFailure('unexpected result: $value');

  static List<Object?> _list(Object? value) =>
      value is List ? value : throw UnknownFailure('unexpected result: $value');

  /// [value] with every object's keys as strings, as the rules' JSON.
  static Object? _json(Object? value) => switch (value) {
    final Map<Object?, Object?> map => <String, Object?>{
      for (final MapEntry(:key, :value) in map.entries) '$key': _json(value),
    },
    final List<Object?> list => [for (final item in list) _json(item)],
    _ => value,
  };

  static StoredRules _stored(Map<Object?, Object?> data) => StoredRules(
    version: (data['version'] as num).toInt(),
    rules: switch (data['rules']) {
      final Map<Object?, Object?> rules => GeneratorRules(
        _json(rules)! as JsonMap,
      ),
      _ => null,
    },
    publishedAt: switch (data['publishedAtMs']) {
      final num millis => DateTime.fromMillisecondsSinceEpoch(millis.toInt()),
      _ => null,
    },
    publishedByEmail: data['publishedByEmail'] as String?,
    note: data['note'] as String?,
    restores: (data['restores'] as num?)?.toInt(),
  );

  static String? _code(Object error) =>
      error is FirebaseFunctionsException ? error.code : null;

  static Failure? _mapError(Object error) {
    if (error is! FirebaseFunctionsException) return mapFirebaseError(error);
    final message = error.message ?? error.code;
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    final problems = details is Map ? details['problems'] : null;
    return switch ((error.code, reason)) {
      (_, _notAdmin) => PermissionFailure(message, error),
      (_, _stale) => GeneratorRulesStaleFailure(message, error),
      (_, _invalidInput) when problems is List => GeneratorRulesInvalidFailure([
        for (final problem in problems) '$problem',
      ], error),
      (_, _invalidInput) => ValidationFailure(message),
      // Not deployed (404), or deployed without permission to call it.
      ('not-found' || 'permission-denied', _) =>
        GeneratorRulesUnavailableFailure(message, error),
      _ => mapFirebaseError(error),
    };
  }
}
