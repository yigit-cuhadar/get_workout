import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/catalogue_program.dart';
import 'package:get_workout/features/programs/domain/catalogue_queries.dart';
import 'package:get_workout/features/programs/domain/program.dart';

import 'fixtures.dart';

void main() {
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

    test('a bodyweight program fits everyone', () {
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
      expect(filter.isEmpty, isTrue);
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

      expect(filter.isEmpty, isFalse);
      expect(ids(filter, owned: {Equipment.dumbbell, Equipment.bench}), ['a']);
      expect(ids(filter, owned: {Equipment.barbell}), ['b']);
      expect(ids(filter), ['a', 'b']);
    });
  });

  group('recommendPrograms', () {
    List<String> recommend(
      List<CatalogueProgram> programs,
      TrainingProfile profile,
    ) => [for (final r in recommendPrograms(programs, profile)) r.program.id];

    test('recommends nothing without answers', () {
      expect(recommend([card('a')], const TrainingProfile()), isEmpty);
    });

    test('scores goal 3, level 2 and days 2; ties keep catalogue order', () {
      final programs = [
        card(
          'level',
          goal: Goal.loseFat,
          level: Level.intermediate,
          daysPerWeek: 5,
        ),
        card('goal', daysPerWeek: 5),
        card('level+days', goal: Goal.loseFat, level: Level.intermediate),
        card('goal2', daysPerWeek: 5),
      ];

      expect(
        recommend(
          programs,
          const TrainingProfile(
            goal: Goal.buildMuscle,
            level: Level.intermediate,
            daysPerWeek: 3,
          ),
        ),
        ['level+days', 'goal', 'goal2'],
      );
    });

    test('says why', () {
      expect(
        recommendPrograms(
          [card('a')],
          const TrainingProfile(
            goal: Goal.buildMuscle,
            level: Level.beginner,
            daysPerWeek: 3,
            equipment: {Equipment.dumbbell, Equipment.bench},
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
    });

    test('a day more or less counts, but is no reason to name', () {
      expect(
        recommendPrograms([
          card('near', daysPerWeek: 4),
          card('far', daysPerWeek: 6),
        ], const TrainingProfile(daysPerWeek: 3)),
        [Recommendation(card('near', daysPerWeek: 4), const [])],
      );
    });

    test('never a harder program, nor one needing equipment the user '
        'lacks', () {
      final programs = [
        card('hard', level: Level.advanced),
        card(
          'gym',
          equipment: const [Equipment.cable],
          profile: EquipmentProfile.fullGym,
        ),
        card('easy'),
      ];

      expect(
        recommend(
          programs,
          const TrainingProfile(
            goal: Goal.buildMuscle,
            level: Level.intermediate,
            equipment: {Equipment.dumbbell, Equipment.bench},
          ),
        ),
        ['easy'],
      );
    });

    test('recommends at most $recommendedCount', () {
      final programs = [for (var i = 0; i < 5; i++) card('p$i', order: i)];

      expect(
        recommend(programs, const TrainingProfile(goal: Goal.buildMuscle)),
        hasLength(recommendedCount),
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
