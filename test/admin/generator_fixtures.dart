import 'dart:convert';
import 'dart:io';

import 'package:get_workout/admin/access/domain/access_usecases.dart';
import 'package:get_workout/admin/generator/domain/generator_rules.dart';
import 'package:get_workout/admin/generator/domain/generator_rules_repository.dart';
import 'package:get_workout/admin/generator/domain/generator_rules_usecases.dart';
import 'package:get_workout/admin/generator/presentation/generator_rules_cubit.dart';
import 'package:mocktail/mocktail.dart';

/// The seed rules (`content/generator/rules.json`), complete and valid.
GeneratorRules seedRules() => GeneratorRules(
  jsonDecode(File('content/generator/rules.json').readAsStringSync())
      as JsonMap,
);

StoredRules storedRules({int version = 3, GeneratorRules? rules}) =>
    StoredRules(
      version: version,
      rules: rules ?? seedRules(),
      publishedAt: DateTime.utc(2026, 11, 22, 10),
      publishedByEmail: 'admin@example.com',
    );

/// The index of the template [id] in the seed.
int seedTemplate(String id) => seedRules().templateIndex(id)!;

class MockRepository extends Mock implements GeneratorRulesRepository {}

class MockCheckAdminAccess extends Mock implements CheckAdminAccess {}

GeneratorRulesCubit makeCubit(
  MockRepository repository, [
  MockCheckAdminAccess? access,
]) => GeneratorRulesCubit(
  loadGeneratorRules: LoadGeneratorRules(repository),
  checkGeneratorRules: CheckGeneratorRules(repository),
  publishGeneratorRules: PublishGeneratorRules(repository),
  loadGeneratorRulesHistory: LoadGeneratorRulesHistory(repository),
  checkAdminAccess: access ?? MockCheckAdminAccess(),
);
