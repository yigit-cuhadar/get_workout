import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/generator/data/callable_generator_rules_repository.dart';
import 'package:get_workout/admin/generator/domain/generator_rules.dart';
import 'package:mocktail/mocktail.dart';

import 'generator_fixtures.dart';

class MockFunctions extends Mock implements FirebaseFunctions {}

class MockCallable extends Mock implements HttpsCallable {}

class MockCallableResult extends Mock implements HttpsCallableResult<Object?> {}

class FunctionsError extends FirebaseFunctionsException {
  FunctionsError(String code, {super.details})
    : super(code: code, message: 'error');
}

void main() {
  late MockFunctions functions;
  late MockCallable callable;
  late MockCallableResult result;
  late CallableGeneratorRulesRepository repository;
  final seed = seedRules();

  setUp(() {
    functions = MockFunctions();
    callable = MockCallable();
    result = MockCallableResult();
    repository = CallableGeneratorRulesRepository(functions);
    when(() => functions.httpsCallable(any())).thenReturn(callable);
    when(() => callable.call<Object?>(any())).thenAnswer((_) async => result);
  });

  void refuse(FirebaseFunctionsException error) =>
      when(() => callable.call<Object?>(any())).thenThrow(error);

  group('load', () {
    test('asks for the current version and reads it', () async {
      when(() => result.data).thenReturn({
        'version': 3,
        // As the callable hands it over: untyped maps.
        'rules': <Object?, Object?>{...seed.json},
        'publishedAtMs': 1795000000000,
        'publishedByEmail': 'admin@example.com',
        'note': null,
        'restores': 2,
      });
      final loaded = (await repository.load()).valueOrNull!;
      expect(loaded.version, 3);
      expect(loaded.rules, seed);
      expect(
        loaded.publishedAt,
        DateTime.fromMillisecondsSinceEpoch(1795000000000),
      );
      expect(loaded.publishedByEmail, 'admin@example.com');
      expect(loaded.note, isNull);
      expect(loaded.restores, 2);
      verify(() => functions.httpsCallable('generatorRulesGet')).called(1);
      verify(() => callable.call<Object?>({'version': null})).called(1);
    });

    test('reads version 0 as no rules', () async {
      when(() => result.data).thenReturn({'version': 0, 'rules': null});
      final loaded = (await repository.load()).valueOrNull!;
      expect(loaded.version, 0);
      expect(loaded.rules, isNull);
    });

    test('asks for a version; a missing one is not found', () async {
      refuse(FunctionsError('not-found'));
      expect(
        (await repository.load(version: 9)).failureOrNull,
        isA<NotFoundFailure>(),
      );
      verify(() => callable.call<Object?>({'version': 9})).called(1);
    });
  });

  test('check sends the rules and reads problems and findings', () async {
    when(() => result.data).thenReturn({
      'problems': ['time.sessionMinutes: must rise'],
      'findings': [
        {
          'goal': 'lose_fat',
          'level': 'beginner',
          'daysPerWeek': 2,
          'equipment': 'bands',
          'kind': 'short',
          'detail': 'Full Body A: 24 min',
        },
      ],
    });
    final check = (await repository.check(seed)).valueOrNull!;
    expect(check.problems, ['time.sessionMinutes: must rise']);
    expect(check.findings, const [
      Finding(
        goal: 'lose_fat',
        level: 'beginner',
        daysPerWeek: 2,
        equipment: 'bands',
        kind: FindingKind.short,
        detail: 'Full Body A: 24 min',
      ),
    ]);
    verify(() => functions.httpsCallable('generatorRulesCheck')).called(1);
    verify(() => callable.call<Object?>({'rules': seed.json})).called(1);
  });

  group('publish', () {
    test('sends base, rules, note and restores; reads the version', () async {
      when(() => result.data).thenReturn({'version': 4});
      final published = await repository.publish(
        RulesPublish(base: 3, rules: seed, note: 'Longer rest', restores: 2),
      );
      expect(published.valueOrNull, 4);
      verify(() => functions.httpsCallable('generatorRulesPublish')).called(1);
      verify(
        () => callable.call<Object?>({
          'base': 3,
          'rules': seed.json,
          'note': 'Longer rest',
          'restores': 2,
        }),
      ).called(1);
    });

    Future<Failure?> refused(FirebaseFunctionsException error) async {
      refuse(error);
      return (await repository.publish(RulesPublish(base: 3, rules: seed)))
          .failureOrNull;
    }

    test('maps each refusal to its failure', () async {
      expect(
        await refused(
          FunctionsError('failed-precondition', details: {'reason': 'stale'}),
        ),
        isA<GeneratorRulesStaleFailure>(),
      );
      expect(
        await refused(
          FunctionsError(
            'invalid-argument',
            details: {
              'reason': 'invalid-input',
              'field': 'rules',
              'problems': ['lengthWeeks.beginner: must be a whole number'],
            },
          ),
        ),
        isA<GeneratorRulesInvalidFailure>().having(
          (failure) => failure.problems,
          'problems',
          ['lengthWeeks.beginner: must be a whole number'],
        ),
      );
      expect(
        await refused(
          FunctionsError(
            'invalid-argument',
            details: {'reason': 'invalid-input', 'field': 'restores'},
          ),
        ),
        isA<ValidationFailure>(),
      );
      expect(
        await refused(
          FunctionsError('permission-denied', details: {'reason': 'not-admin'}),
        ),
        isA<PermissionFailure>(),
      );
      expect(
        await refused(FunctionsError('not-found')),
        isA<GeneratorRulesUnavailableFailure>(),
      );
      expect(
        await refused(FunctionsError('unavailable')),
        isA<NetworkFailure>(),
      );
    });
  });

  test('history reads the versions without rules', () async {
    when(() => result.data).thenReturn([
      {
        'version': 2,
        'publishedAtMs': null,
        'publishedByEmail': null,
        'note': 'Seed',
        'restores': null,
      },
    ]);
    final history = (await repository.history()).valueOrNull!;
    expect(history, const [StoredRules(version: 2, note: 'Seed')]);
    verify(() => functions.httpsCallable('generatorRulesHistory')).called(1);
    verify(() => callable.call<Object?>(null)).called(1);
  });
}
