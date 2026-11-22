import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../../features/generator/data/server_generator_repository.dart';
import '../../../features/generator/domain/generator_repository.dart';
import '../domain/generator_rules.dart';
import '../domain/generator_rules_repository.dart';
import '../domain/simulation.dart';

/// [GeneratorRulesRepository] on the callables `generatorRulesGet`,
/// `generatorRulesCheck`, `generatorRulesPublish` and
/// `generatorRulesHistory` (`functions/src/generator/store.ts`), and
/// `generateProgram` (`generation.ts`) for the simulator.
class CallableGeneratorRulesRepository implements GeneratorRulesRepository {
  const CallableGeneratorRulesRepository(this._functions);

  final FirebaseFunctions _functions;

  static const getFunction = 'generatorRulesGet';
  static const checkFunction = 'generatorRulesCheck';
  static const publishFunction = 'generatorRulesPublish';
  static const historyFunction = 'generatorRulesHistory';
  static const generateFunction = ServerGeneratorRepository.function;

  /// `details.reason` values of the functions' refusals.
  static const _notAdmin = 'not-admin';
  static const _invalidInput = 'invalid-input';
  static const _stale = 'stale';
  static const _refusals = {
    'no-rules': GenerationRefusal.noRules,
    'no-template': GenerationRefusal.noTemplate,
    'no-exercises': GenerationRefusal.noExercises,
  };

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

  @override
  Future<Result<Simulation>> simulate(SimulationRequest request) =>
      guard(() async {
        final data = await _call(generateFunction, {
          ...ServerGeneratorRepository.requestData((
            answers: request.answers,
            seed: request.seed,
            kept: const [],
            language: 'en',
          )),
          'rules': ?request.rules?.json,
          'explain': true,
        });
        final result = _map(data);
        return Simulation(
          program: ServerGeneratorRepository.programFrom(data),
          split: '${result['split']}',
          template: '${result['template']}',
          weeklySets: {
            for (final MapEntry(:key, :value) in _map(
              result['weeklySets'],
            ).entries)
              if ((Muscle.values.byCode(key), value) case (
                final muscle?,
                final num sets,
              ))
                muscle: sets.toDouble(),
          },
          rulesVersion: (result['rulesVersion'] as num).toInt(),
          trace: [
            for (final day in _list(result['trace']))
              [for (final why in _list(day)) _reason(_map(why))],
          ],
        );
      }, mapper: _mapError);

  static PickReason _reason(Map<Object?, Object?> why) => PickReason(
    exerciseId: '${why['exerciseId']}',
    role:
        SlotRole.values.byCode(why['role']) ??
        (throw UnknownFailure('unexpected role: ${why['role']}')),
    priority: (why['priority'] as num).toInt(),
    source: PickSource.values.byName('${why['source']}'),
    score: {
      if (why['score'] case final Map<Object?, Object?> score)
        for (final MapEntry(:key, :value) in score.entries)
          '$key': (value! as num).toDouble(),
    },
    others: [
      for (final other in _list(why['others'] ?? const <Object?>[]))
        if (_map(other) case final other)
          (
            exerciseId: '${other['exerciseId']}',
            score: (other['score'] as num).toDouble(),
          ),
    ],
  );

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
      (_, final String reason) when _refusals.containsKey(reason) =>
        GenerationRefused(_refusals[reason]!, message, cause: error),
      // Not deployed (404), or deployed without permission to call it.
      ('not-found' || 'permission-denied', _) =>
        GeneratorRulesUnavailableFailure(message, error),
      _ => mapFirebaseError(error),
    };
  }
}
