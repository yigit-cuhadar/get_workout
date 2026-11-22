import 'dart:convert';
import 'dart:io';

import 'package:get_workout/admin/access/domain/access_usecases.dart';
import 'package:get_workout/admin/generator/domain/simulation.dart';
import 'package:get_workout/admin/generator/domain/generator_rules.dart';
import 'package:get_workout/admin/generator/domain/generator_rules_repository.dart';
import 'package:get_workout/admin/generator/domain/generator_rules_usecases.dart';
import 'package:get_workout/admin/generator/presentation/generator_rules_cubit.dart';
import 'package:get_workout/admin/generator/presentation/rules_text.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/generator/domain/generated_program.dart';
import 'package:get_workout/features/programs/domain/program.dart';
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

/// Where each of [state]'s changes is, as the review words it.
List<String> wheres(GeneratorRulesState state) => [
  for (final change in state.changes)
    changeLine(change, state.rules!, state.draft!).where,
];

/// `generateProgram`'s answer with `explain: true`, as the callable hands
/// it over: two days, a scored item, one shared by key and a hold.
Map<Object?, Object?> simulationData() => {
  'program': {
    'name': 'Upper / Lower',
    'lengthWeeks': 10,
    'days': [
      {
        'name': 'Upper A',
        'items': [
          {
            'exerciseId': 'bench_press',
            'sets': 4,
            'repMin': 6,
            'repMax': 10,
            'restS': 150,
          },
          {'exerciseId': 'plank', 'sets': 3, 'durationS': 30, 'restS': 45},
        ],
      },
      {
        'name': 'Lower A',
        'items': [
          {
            'exerciseId': 'leg_press',
            'sets': 3,
            'repMin': 8,
            'repMax': 12,
            'restS': 120,
          },
        ],
      },
    ],
  },
  'split': 'upper_lower',
  'template': 'upper_lower_4',
  'weeklySets': {'pec': 4, 'triceps': 2, 'quads': 3, 'abdominal': 1.5},
  'targeted': ['pec', 'quads', 'abdominal'],
  'uncovered': ['abdominal'],
  'rulesVersion': 3,
  'trace': [
    [
      {
        'exerciseId': 'bench_press',
        'role': 'primary',
        'priority': 1,
        'source': 'slot',
        'score': {
          'tier': 30,
          'equipment': 12,
          'popularity': 18.5,
          'variety': 0.9,
        },
        'others': [
          {'exerciseId': 'dumbbell_press', 'score': 44.1},
          {'exerciseId': 'machine_press', 'score': 39.8},
        ],
      },
      {
        'exerciseId': 'plank',
        'role': 'core',
        'priority': 2,
        'source': 'key',
        'others': <Object?>[],
      },
    ],
    [
      {
        'exerciseId': 'leg_press',
        'role': 'secondary',
        'priority': 1,
        'source': 'extra',
        'score': {'tier': 20, 'aboveLevel': -5},
        'others': <Object?>[],
      },
    ],
  ],
};

/// [simulationData] as the repository reads it.
Simulation simulation() => const Simulation(
  program: GeneratedProgram(
    splitName: 'Upper / Lower',
    lengthWeeks: 10,
    days: [
      ProgramDay(
        name: 'Upper A',
        items: [
          ProgramItem(
            exerciseId: 'bench_press',
            sets: 4,
            repMin: 6,
            repMax: 10,
            restS: 150,
          ),
          ProgramItem(exerciseId: 'plank', sets: 3, durationS: 30, restS: 45),
        ],
      ),
      ProgramDay(
        name: 'Lower A',
        items: [
          ProgramItem(
            exerciseId: 'leg_press',
            sets: 3,
            repMin: 8,
            repMax: 12,
            restS: 120,
          ),
        ],
      ),
    ],
    targeted: {Muscle.pec, Muscle.quads, Muscle.abdominal},
    uncovered: {Muscle.abdominal},
  ),
  split: 'upper_lower',
  template: 'upper_lower_4',
  weeklySets: {
    Muscle.pec: 4,
    Muscle.triceps: 2,
    Muscle.quads: 3,
    Muscle.abdominal: 1.5,
  },
  rulesVersion: 3,
  trace: [
    [
      PickReason(
        exerciseId: 'bench_press',
        role: SlotRole.primary,
        priority: 1,
        source: PickSource.slot,
        score: {
          'tier': 30,
          'equipment': 12,
          'popularity': 18.5,
          'variety': 0.9,
        },
        others: [
          (exerciseId: 'dumbbell_press', score: 44.1),
          (exerciseId: 'machine_press', score: 39.8),
        ],
      ),
      PickReason(
        exerciseId: 'plank',
        role: SlotRole.core,
        priority: 2,
        source: PickSource.key,
      ),
    ],
    [
      PickReason(
        exerciseId: 'leg_press',
        role: SlotRole.secondary,
        priority: 1,
        source: PickSource.extra,
        score: {'tier': 20, 'aboveLevel': -5},
      ),
    ],
  ],
);
