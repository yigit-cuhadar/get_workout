import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/catalogue_program.dart';
import 'package:get_workout/features/programs/domain/catalogue_queries.dart';
import 'package:get_workout/features/programs/domain/program.dart';

import 'fixtures.dart';

void main() {
  group('suits', () {
    final program = card('p', goal: Goal.getStronger, level: Level.advanced);
    const profile = TrainingProfile(
      goal: Goal.getStronger,
      level: Level.advanced,
      daysPerWeek: 3,
    );

    test('a program for the goal, level and days per week fits', () {
      expect(profile.suits(program), isTrue);
    });

    test('any answer that differs or is missing does not', () {
      expect(
        const TrainingProfile(
          goal: Goal.getStronger,
          level: Level.advanced,
          daysPerWeek: 4,
        ).suits(program),
        isFalse,
      );
      expect(
        const TrainingProfile(
          goal: Goal.getStronger,
          level: Level.beginner,
          daysPerWeek: 3,
        ).suits(program),
        isFalse,
      );
      expect(
        const TrainingProfile(
          level: Level.advanced,
          daysPerWeek: 3,
        ).suits(program),
        isFalse,
      );
    });
  });

  group('fits', () {
    final gym = card(
      'gym',
      equipment: const [
        Equipment.barbell,
        Equipment.cable,
        Equipment.bodyweight,
      ],
      profile: EquipmentProfile.fullGym,
    );

    test('needs every primary equipment, bodyweight aside', () {
      expect(gym.fits({Equipment.barbell, Equipment.cable}), isTrue);
      expect(gym.fits({Equipment.barbell}), isFalse);
    });

    test('or everything of its equipment profile', () {
      final home = card(
        'home',
        equipment: const [Equipment.ezBar, Equipment.dumbbell],
        profile: EquipmentProfile.dumbbells,
      );

      expect(home.fits({Equipment.dumbbell, Equipment.bench}), isTrue);
      expect(home.fits({Equipment.dumbbell}), isFalse);
    });

    test('an unknown equipment list fits only through the profile', () {
      final unknown = card('u', equipment: null);

      expect(unknown.fits({Equipment.dumbbell}), isFalse);
      expect(unknown.fits({Equipment.dumbbell, Equipment.bench}), isTrue);
    });

    test('a program of bodyweight exercises only fits everyone', () {
      final bodyweight = card(
        'bw',
        equipment: const [Equipment.bodyweight],
        profile: EquipmentProfile.bodyweight,
      );

      expect(bodyweight.fits(const {}), isTrue);
    });
  });

  group('CatalogueFilter', () {
    final a = card('a');
    final b = card(
      'b',
      level: Level.advanced,
      goal: Goal.getStronger,
      daysPerWeek: 5,
      equipment: const [Equipment.barbell],
      profile: EquipmentProfile.fullGym,
    );

    List<String> ids(CatalogueFilter filter, {Set<Equipment>? owned}) => [
      for (final p in [a, b])
        if (filter.matches(p, owned)) p.id,
    ];

    test('an empty filter lets everything through', () {
      const filter = CatalogueFilter();
      expect(filter.isActive(const {}), isFalse);
      expect(ids(filter), ['a', 'b']);
    });

    test('each set allows any of its values', () {
      expect(ids(const CatalogueFilter(levels: {Level.advanced})), ['b']);
      expect(ids(const CatalogueFilter(daysPerWeek: {3, 4})), ['a']);
      expect(ids(const CatalogueFilter(goals: {Goal.getStronger})), ['b']);
      expect(
        ids(const CatalogueFilter(profiles: {EquipmentProfile.dumbbells})),
        ['a'],
      );
    });

    test('filters combine', () {
      expect(
        ids(
          const CatalogueFilter(
            levels: {Level.beginner},
            goals: {Goal.getStronger},
          ),
        ),
        isEmpty,
      );
    });

    test('fits my equipment applies once the equipment is known', () {
      const filter = CatalogueFilter(fitsMyEquipment: true);

      expect(filter.isActive({Equipment.barbell}), isTrue);
      expect(filter.isActive(null), isFalse);
      expect(ids(filter, owned: {Equipment.dumbbell, Equipment.bench}), ['a']);
      expect(ids(filter, owned: {Equipment.barbell}), ['b']);
      expect(ids(filter), ['a', 'b']);
    });

    test('counts each chosen value, fits my equipment once known', () {
      const filter = CatalogueFilter(
        levels: {Level.beginner, Level.advanced},
        daysPerWeek: {3},
        goals: {Goal.getStronger},
        profiles: {EquipmentProfile.dumbbells},
        fitsMyEquipment: true,
      );

      expect(filter.activeCount({Equipment.barbell}), 6);
      expect(filter.activeCount(null), 5);
      expect(const CatalogueFilter().activeCount(const {}), 0);
    });
  });

  group('equipment type', () {
    test('a set equal to a preset is that preset', () {
      for (final preset in EquipmentProfile.values) {
        expect(EquipmentProfile.typeOf(preset.equipment), preset);
      }
    });

    test('a custom set is the most similar preset', () {
      // 3 of 5 items with the home gym, 1 of 4 with dumbbells.
      expect(
        EquipmentProfile.typeOf(const {
          Equipment.barbell,
          Equipment.plate,
          Equipment.dumbbell,
        }),
        EquipmentProfile.homeGym,
      );
      // The full gym shares all three but has far more; dumbbells share 2
      // of 3.
      expect(
        EquipmentProfile.typeOf(const {
          Equipment.dumbbell,
          Equipment.bench,
          Equipment.resistanceBand,
        }),
        EquipmentProfile.dumbbells,
      );
      // A gym missing one item is still a gym.
      expect(
        EquipmentProfile.typeOf(
          EquipmentProfile.fullGym.equipment.difference(const {
            Equipment.cable,
          }),
        ),
        EquipmentProfile.fullGym,
      );
    });

    test('a tie goes to the smaller preset', () {
      // Shares 1 with the full gym, the home gym and dumbbells.
      expect(
        EquipmentProfile.typeOf(const {Equipment.dumbbell}),
        EquipmentProfile.dumbbells,
      );
      // Shares 1 with the full gym, the home gym and bodyweight.
      expect(
        EquipmentProfile.typeOf(const {Equipment.pullUpBar}),
        EquipmentProfile.bodyweight,
      );
    });

    test('nothing shared, or nothing owned, is bodyweight', () {
      expect(EquipmentProfile.typeOf(const {}), EquipmentProfile.bodyweight);
      expect(
        EquipmentProfile.typeOf(const {Equipment.bodyweight}),
        EquipmentProfile.bodyweight,
      );
    });
  });

  group('recommendPrograms', () {
    List<String> recommend(
      List<CatalogueProgram> programs,
      TrainingProfile profile,
    ) => [for (final r in recommendPrograms(programs, profile)) r.program.id];

    const dumbbells = {Equipment.dumbbell, Equipment.bench};

    test('never another equipment type, with less or more equipment', () {
      final programs = [
        card('gym', profile: EquipmentProfile.fullGym),
        card('bands', profile: EquipmentProfile.bands),
        card('home', profile: EquipmentProfile.homeGym),
        card('fits'),
      ];

      expect(recommend(programs, const TrainingProfile(equipment: dumbbells)), [
        'fits',
      ]);
    });

    test('a custom set recommends its closest preset\'s programs', () {
      final programs = [
        card('dumbbells'),
        card('home', profile: EquipmentProfile.homeGym),
      ];

      expect(
        recommend(
          programs,
          const TrainingProfile(
            equipment: {Equipment.barbell, Equipment.plate, Equipment.dumbbell},
          ),
        ),
        ['home'],
      );
    });

    test('no equipment recommends bodyweight programs', () {
      final programs = [
        card('dumbbells'),
        card('bodyweight', profile: EquipmentProfile.bodyweight),
      ];

      expect(recommend(programs, const TrainingProfile(equipment: {})), [
        'bodyweight',
      ]);
    });

    test('never more than one level from the user\'s', () {
      final programs = [
        card('beginner'),
        card('intermediate', level: Level.intermediate),
        card('advanced', level: Level.advanced),
      ];

      expect(
        recommend(programs, const TrainingProfile(level: Level.beginner)),
        ['beginner', 'intermediate'],
      );
      expect(
        recommend(programs, const TrainingProfile(level: Level.advanced)),
        ['advanced', 'intermediate'],
      );
      expect(
        recommend(programs, const TrainingProfile(level: Level.intermediate)),
        ['intermediate', 'beginner', 'advanced'],
      );
    });

    test('never more than one day from the user\'s', () {
      final programs = [
        card('2', daysPerWeek: 2),
        card('3'),
        card('4', daysPerWeek: 4),
        card('5', daysPerWeek: 5),
        card('6', daysPerWeek: 6),
      ];

      expect(recommend(programs, const TrainingProfile(daysPerWeek: 4)), [
        '4',
        '3',
        '5',
      ]);
    });

    test('goal: 3 for the same, 1 for a related one, 0 otherwise', () {
      List<int> scores(Goal user) {
        final programs = [
          for (final goal in Goal.values) card(goal.code, goal: goal),
        ];
        final ranked = recommend(programs, TrainingProfile(goal: user));
        return [for (final goal in Goal.values) ranked.indexOf(goal.code)];
      }

      // By rank: the same goal, the related one, then the other two in
      // catalogue order (only three are returned).
      expect(scores(Goal.buildMuscle), [0, 1, 2, -1]);
      expect(scores(Goal.getStronger), [1, 0, 2, -1]);
      expect(scores(Goal.loseFat), [2, -1, 0, 1]);
      expect(scores(Goal.generalFitness), [2, -1, 1, 0]);
    });

    test('a related goal (1) outranks no match (0)', () {
      final programs = [
        card('other', goal: Goal.loseFat),
        card('related', goal: Goal.getStronger),
      ];

      expect(
        recommend(programs, const TrainingProfile(goal: Goal.buildMuscle)),
        ['related', 'other'],
      );
    });

    test('level: 2 for the same, 1 for one below, 0 for one above', () {
      final programs = [
        card('above', level: Level.advanced, goal: Goal.loseFat),
        card('below', goal: Goal.loseFat),
        card('same', level: Level.intermediate, goal: Goal.loseFat),
      ];

      expect(
        recommend(programs, const TrainingProfile(level: Level.intermediate)),
        ['same', 'below', 'above'],
      );
      // One below (1) ties a related goal (1); above (0) ties nothing.
      expect(
        recommend(
          [
            card('above', level: Level.advanced, goal: Goal.loseFat),
            card('related', level: Level.advanced, goal: Goal.getStronger),
            card('below', goal: Goal.loseFat),
          ],
          const TrainingProfile(
            goal: Goal.buildMuscle,
            level: Level.intermediate,
          ),
        ),
        ['related', 'below', 'above'],
      );
    });

    test('days: 2 for the same, 1 for a day more or fewer', () {
      final programs = [
        card('more', daysPerWeek: 4),
        card('same'),
        card('fewer', daysPerWeek: 2),
      ];

      expect(recommend(programs, const TrainingProfile(daysPerWeek: 3)), [
        'same',
        'more',
        'fewer',
      ]);
    });

    test('the weights add up: goal 3 beats level 2 or days 2', () {
      final programs = [
        card(
          'level+days',
          goal: Goal.loseFat,
          level: Level.intermediate,
          daysPerWeek: 4,
        ),
        card('goal', level: Level.advanced, daysPerWeek: 5),
        card(
          'level',
          goal: Goal.loseFat,
          level: Level.intermediate,
          daysPerWeek: 5,
        ),
        card('goal+days', level: Level.advanced, daysPerWeek: 4),
      ];

      expect(
        recommend(
          programs,
          const TrainingProfile(
            goal: Goal.buildMuscle,
            level: Level.intermediate,
            daysPerWeek: 4,
          ),
        ),
        // 5 (3+2), then 4 (2+2) and 4 (3+1) in catalogue order, before 3.
        ['goal+days', 'level+days', 'goal'],
      );
    });

    test('ties keep catalogue order; premium makes no difference', () {
      final programs = [
        card('a', premium: true),
        card('b'),
        card('c', premium: true),
        card('d'),
      ];

      expect(
        recommend(programs, const TrainingProfile(goal: Goal.buildMuscle)),
        ['a', 'b', 'c'],
      );
    });

    test('at most $recommendedCount; fewer when fewer are left', () {
      final programs = [for (var i = 0; i < 5; i++) card('p$i', order: i)];

      expect(
        recommend(programs, const TrainingProfile(goal: Goal.buildMuscle)),
        hasLength(recommendedCount),
      );
      expect(
        recommend([
          card('fits'),
          card('far', daysPerWeek: 6),
        ], const TrainingProfile(daysPerWeek: 3)),
        ['fits'],
      );
      expect(
        recommend([
          card('far', daysPerWeek: 6),
        ], const TrainingProfile(daysPerWeek: 3)),
        isEmpty,
      );
    });

    test('unknown answers leave nothing out and score nothing', () {
      final programs = [
        card('gym', level: Level.advanced, profile: EquipmentProfile.fullGym),
        card('six', daysPerWeek: 6, goal: Goal.loseFat),
        card('bands', profile: EquipmentProfile.bands),
      ];

      expect(recommend(programs, const TrainingProfile()), [
        'gym',
        'six',
        'bands',
      ]);
      expect(
        recommendPrograms(programs, const TrainingProfile()).first.reasons,
        isEmpty,
      );
    });

    test('names only exact matches, and the equipment once known', () {
      expect(
        recommendPrograms(
          [card('a')],
          const TrainingProfile(
            goal: Goal.buildMuscle,
            level: Level.beginner,
            daysPerWeek: 3,
            equipment: dumbbells,
          ),
        ),
        [
          Recommendation(card('a'), const [
            MatchReason.goal,
            MatchReason.level,
            MatchReason.days,
            MatchReason.equipment,
          ]),
        ],
      );
      // A related goal, one level below and a day more: no reason to name.
      expect(
        recommendPrograms(
          [card('near', goal: Goal.getStronger, daysPerWeek: 4)],
          const TrainingProfile(
            goal: Goal.buildMuscle,
            level: Level.intermediate,
            daysPerWeek: 3,
          ),
        ),
        [
          Recommendation(
            card('near', goal: Goal.getStronger, daysPerWeek: 4),
            const [],
          ),
        ],
      );
    });
  });

  test('a copy is the user\'s, linked to the catalogue program', () {
    final days = [
      ProgramDay(name: 'A', items: [item('a')]),
    ];
    final copy = card('pr_x', lengthWeeks: 8).copy(days, 'en');

    expect(
      copy,
      Program(
        name: 'Program pr_x',
        origin: ProgramOrigin.catalog,
        sourceId: 'pr_x',
        lengthWeeks: 8,
        days: days,
      ),
    );
  });
}
