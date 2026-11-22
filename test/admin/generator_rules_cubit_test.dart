import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/generator/domain/generator_rules.dart';
import 'package:get_workout/admin/generator/domain/rules_changes.dart';
import 'package:get_workout/admin/generator/presentation/generator_rules_cubit.dart';
import 'package:get_workout/admin/generator/presentation/rules_text.dart';
import 'package:mocktail/mocktail.dart';

import 'generator_fixtures.dart';

const _rest = ['dosing', 'build_muscle', 'primary', 'restS'];

const _finding = Finding(
  goal: 'lose_fat',
  level: 'beginner',
  daysPerWeek: 2,
  equipment: 'bands',
  kind: FindingKind.short,
  detail: 'Full Body A: 24 min',
);

void main() {
  final seed = seedRules();
  late MockRepository repository;

  setUpAll(() {
    registerFallbackValue(seed);
    registerFallbackValue(RulesPublish(base: 0, rules: seed));
  });

  setUp(() {
    repository = MockRepository();
    when(() => repository.load())
        .thenAnswer((_) async => Ok(storedRules(rules: seed)));
    when(() => repository.check(any()))
        .thenAnswer((_) async => const Ok(RulesCheck()));
  });

  Future<GeneratorRulesCubit> loadedCubit() async {
    final cubit = makeCubit(repository);
    addTearDown(cubit.close);
    await cubit.load();
    return cubit;
  }

  group('load', () {
    blocTest<GeneratorRulesCubit, GeneratorRulesState>(
      'takes the current version as the draft, with no changes',
      build: () => makeCubit(repository),
      act: (cubit) => cubit.load(),
      verify: (cubit) {
        final state = cubit.state;
        expect(state.loaded?.version, 3);
        expect(state.draft, seed);
        expect(state.hasChanges, isFalse);
        expect(state.canPublish, isFalse);
      },
    );

    blocTest<GeneratorRulesCubit, GeneratorRulesState>(
      'with version 0 has nothing to edit',
      setUp: () =>
          when(() => repository.load())
              .thenAnswer((_) async => const Ok(StoredRules(version: 0))),
      build: () => makeCubit(repository),
      act: (cubit) {
        cubit.load();
        cubit.setValue(_rest, 165);
      },
      verify: (cubit) {
        expect(cubit.state.loaded?.version, 0);
        expect(cubit.state.draft, isNull);
        expect(cubit.state.hasChanges, isFalse);
      },
    );

    blocTest<GeneratorRulesCubit, GeneratorRulesState>(
      'keeps the last loaded when a reload fails',
      build: () => makeCubit(repository),
      act: (cubit) async {
        await cubit.load();
        when(() => repository.load())
            .thenAnswer((_) async => const Err(NetworkFailure()));
        await cubit.load();
      },
      verify: (cubit) {
        expect(cubit.state.loaded?.version, 3);
        expect(cubit.state.loadFailure, isA<NetworkFailure>());
      },
    );
  });

  group('edits', () {
    test('mark their tabs; setting a value back takes it back', () async {
      final cubit = await loadedCubit();
      cubit
        ..setValue(_rest, 165)
        ..setValue(['volume', 'cap', 'beginner'], 16);
      expect(wheres(cubit.state), [
        'Dosing · Build muscle · Primary · rest',
        'Volume · cap · Beginner',
      ]);
      expect(cubit.state.changedTabs, [RulesTab.dosing, RulesTab.volume]);
      expect(cubit.state.wasAt(_rest), '150');
      expect(cubit.state.wasAt(['volume', 'cap', 'advanced']), isNull);

      cubit.setValue(_rest, 150);
      expect(cubit.state.changedTabs, [RulesTab.volume]);
    });

    test('discard takes the draft back to the loaded rules', () async {
      final cubit = await loadedCubit();
      cubit
        ..setValue(_rest, 165)
        ..discard();
      expect(cubit.state.draft, seed);
      expect(cubit.state.hasChanges, isFalse);
    });

    test('templates: add opens it, days grow and shrink, remove', () async {
      final cubit = await loadedCubit();
      final count = seed.templates.length;
      cubit.addTemplate();
      expect(cubit.state.openTemplate, count);
      expect(wheres(cubit.state).single, 'Template new_template added');

      cubit.setDays(count, 5);
      expect(cubit.state.valueAt(['templates', count, 'days']), 5);
      expect(
        cubit.state.valueAt(['templates', count, 'dayList']),
        hasLength(5),
      );
      cubit.selectDay(4);
      cubit.setDays(count, 2);
      expect(
        cubit.state.valueAt(['templates', count, 'dayList']),
        hasLength(2),
      );
      expect(cubit.state.openDay, 1);

      cubit.removeTemplate(count);
      expect(cubit.state.hasChanges, isFalse);
      expect(cubit.state.openTemplate, count - 1);
    });

    test('a problem opens its tab, template and day, or goal', () async {
      final cubit = await loadedCubit();
      cubit.openProblem(
        RulesProblem.parse('templates[4].dayList[2].slots[0].pick: x'),
      );
      expect(
        (cubit.state.tab, cubit.state.template, cubit.state.day),
        (RulesTab.templates, 4, 2),
      );
      cubit.openProblem(RulesProblem.parse('dosing.lose_fat.core.restS: x'));
      expect(
        (cubit.state.tab, cubit.state.dosingGoal),
        (RulesTab.dosing, 'lose_fat'),
      );
    });
  });

  group('check', () {
    test('runs a second after the last edit, with the draft', () {
      fakeAsync((async) {
        final cubit = makeCubit(repository)..load();
        async.flushMicrotasks();
        cubit.setValue(_rest, 160);
        async.elapse(const Duration(milliseconds: 600));
        cubit.setValue(_rest, 165);
        async.elapse(const Duration(milliseconds: 600));
        verifyNever(() => repository.check(any()));

        async.elapse(const Duration(milliseconds: 500));
        verify(() => repository.check(seed.set(_rest, 165))).called(1);
        expect(cubit.state.draftChecked, isTrue);
        cubit.close();
      });
    });

    test('maps the problems to their tabs and blocks the review', () {
      fakeAsync((async) {
        when(() => repository.check(any())).thenAnswer(
          (_) async => const Ok(
            RulesCheck(
              problems: [
                'dosing.build_muscle.primary.restS: must be a whole number '
                    'from 0 to 600',
                'templates[0].dayList[1].slots[2].pick: needs patterns or '
                    'muscles',
              ],
            ),
          ),
        );
        final cubit = makeCubit(repository)..load();
        async.flushMicrotasks();
        cubit.setValue(_rest, 900);
        async.elapse(GeneratorRulesCubit.checkDelay);
        expect(cubit.state.problemTabs, {RulesTab.dosing, RulesTab.templates});
        expect(cubit.state.problemsAt(_rest), [
          'must be a whole number from 0 to 600',
        ]);
        expect(cubit.state.canPublish, isFalse);
        cubit.close();
      });
    });

    test('an edit back to the loaded rules clears it without asking', () {
      fakeAsync((async) {
        final cubit = makeCubit(repository)..load();
        async.flushMicrotasks();
        cubit
          ..setValue(_rest, 165)
          ..setValue(_rest, 150);
        async.elapse(const Duration(seconds: 2));
        verifyNever(() => repository.check(any()));
        cubit.close();
      });
    });
  });

  group('review', () {
    test('checks the draft, and the loaded rules once a version', () async {
      final draft = seed.set(_rest, 165);
      when(() => repository.check(seed))
          .thenAnswer((_) async => const Ok(RulesCheck(findings: [_finding])));
      final cubit = await loadedCubit();
      cubit.setValue(_rest, 165);
      await cubit.review();
      expect(cubit.state.draftChecked, isTrue);
      expect(cubit.state.loadedFindings, [_finding]);
      expect(cubit.state.canPublish, isTrue);

      await cubit.review();
      verify(() => repository.check(seed)).called(1);
      verify(() => repository.check(draft)).called(1);
    });
  });

  group('publish', () {
    Future<GeneratorRulesCubit> reviewed() async {
      final cubit = await loadedCubit();
      cubit.setValue(_rest, 165);
      await cubit.review();
      return cubit;
    }

    test('publishes onto the loaded version, then shows the new one', () async {
      final draft = seed.set(_rest, 165);
      when(() => repository.publish(any())).thenAnswer((_) async {
        when(() => repository.load())
            .thenAnswer((_) async => Ok(storedRules(version: 4, rules: draft)));
        return const Ok(4);
      });
      final cubit = await reviewed();
      await cubit.publish('  Longer rest  ');
      verify(
        () => repository.publish(
          RulesPublish(base: 3, rules: draft, note: 'Longer rest'),
        ),
      ).called(1);
      expect(cubit.state.loaded?.version, 4);
      expect(cubit.state.hasChanges, isFalse);
    });

    test('stale keeps the draft, compared with the new version', () async {
      when(() => repository.publish(any()))
          .thenAnswer((_) async => const Err(GeneratorRulesStaleFailure()));
      final cubit = await reviewed();
      await cubit.publish('');
      expect(cubit.state.stale, isTrue);
      expect(cubit.state.hasChanges, isTrue);
      cubit.setValue(['volume', 'cap', 'advanced'], 21);
      expect(cubit.state.stale, isTrue);
      cubit.setValue(['volume', 'cap', 'advanced'], 22);

      final theirs = seed.set(['volume', 'cap', 'beginner'], 18);
      when(() => repository.load())
          .thenAnswer((_) async => Ok(storedRules(version: 4, rules: theirs)));
      await cubit.load();
      expect(cubit.state.loaded?.version, 4);
      expect(cubit.state.stale, isFalse);
      expect(cubit.state.draft, seed.set(_rest, 165));
      expect(wheres(cubit.state), [
        'Dosing · Build muscle · Primary · rest',
        'Volume · cap · Beginner',
      ]);
    });

    test('invalid shows the problems and blocks publishing', () async {
      when(() => repository.publish(any())).thenAnswer(
        (_) async => const Err(
          GeneratorRulesInvalidFailure(['lengthWeeks.beginner: too long']),
        ),
      );
      final cubit = await reviewed();
      await cubit.publish('');
      expect(cubit.state.publishStatus, PublishStatus.failed);
      expect(cubit.state.problemTabs, {RulesTab.areas});
      expect(cubit.state.canPublish, isFalse);
    });

    test('a refused claim refreshes the token to tell', () async {
      final access = MockCheckAdminAccess();
      when(() => access(true)).thenAnswer((_) async => const Ok(true));
      when(() => repository.publish(any()))
          .thenAnswer((_) async => const Err(PermissionFailure()));
      final cubit = makeCubit(repository, access);
      addTearDown(cubit.close);
      await cubit.load();
      cubit.setValue(_rest, 165);
      await cubit.review();
      await cubit.publish('');
      expect(cubit.state.publishFailure, isA<PermissionFailure>());
      expect(cubit.state.accessRefreshed, isTrue);
    });
  });

  group('history', () {
    final older = seed.set(_rest, 120);

    setUp(() {
      when(() => repository.history()).thenAnswer(
        (_) async => const Ok([
          StoredRules(version: 3),
          StoredRules(version: 2, note: 'Shorter rest'),
        ]),
      );
      when(() => repository.load(version: 2))
          .thenAnswer((_) async => Ok(storedRules(version: 2, rules: older)));
    });

    test('opens once loaded, and a restore fills the draft', () async {
      when(() => repository.publish(any()))
          .thenAnswer((_) async => const Ok(4));
      final cubit = await loadedCubit();
      await cubit.openHistory();
      expect(cubit.state.history?.map((v) => v.version), [3, 2]);

      await cubit.restore(2);
      expect(cubit.state.draft, older);
      expect(cubit.state.restores, 2);
      expect(cubit.state.changes.single.after, 120);

      await cubit.review();
      await cubit.publish('');
      verify(
        () => repository.publish(
          RulesPublish(base: 3, rules: older, restores: 2),
        ),
      ).called(1);
    });

    test('an edit after a restore no longer restores', () async {
      final cubit = await loadedCubit();
      await cubit.restore(2);
      cubit.setValue(['volume', 'cap', 'beginner'], 16);
      expect(cubit.state.restores, isNull);
    });
  });

  group('review fixes', () {
    test('a new template stays new while its id is typed', () async {
      final cubit = await loadedCubit();
      cubit.addTemplate();
      final t = cubit.state.openTemplate!;
      for (final id in ['f', 'full_body_3', 'full_body_3_home']) {
        cubit.setValue(['templates', t, 'id'], id);
        expect(cubit.state.newTemplates, {t});
        expect(cubit.state.changes.map((c) => c.kind), [ChangeKind.added]);
        expect(cubit.state.wasAt(['templates', t, 'days']), isNull);
      }
    });

    test('a structural edit drops the last check at once', () async {
      when(() => repository.check(any())).thenAnswer(
        (_) async => const Ok(
          RulesCheck(problems: ['grouping[1].size: must be a whole number']),
        ),
      );
      final cubit = await loadedCubit();
      cubit.setValue(['grouping', 1, 'size'], 9);
      await cubit.checkDraft();
      expect(cubit.state.problems, isNotEmpty);

      cubit.moveItem(['grouping'], 1, 0);
      expect(cubit.state.problems, isEmpty);
      expect(cubit.state.checkDue, isTrue);
      expect(cubit.state.canPublish, isFalse);
    });

    test(
      'a value edit leaves publishing to a check of the new draft',
      () async {
        final cubit = await loadedCubit();
        cubit.setValue(_rest, 160);
        await cubit.checkDraft();
        expect(cubit.state.canPublish, isTrue);
        cubit.setValue(_rest, 165);
        expect(cubit.state.canPublish, isFalse);
        expect(cubit.state.checkDue, isTrue);
      },
    );

    test('a slow check answer after a newer one is ignored', () async {
      final slow = Completer<Result<RulesCheck>>();
      final first = seed.set(_rest, 160);
      when(() => repository.check(first)).thenAnswer((_) => slow.future);
      final cubit = await loadedCubit();
      cubit.setValue(_rest, 160);
      final pending = cubit.checkDraft();
      cubit.setValue(_rest, 165);
      await cubit.checkDraft();
      slow.complete(
        const Ok(RulesCheck(problems: ['dosing.build_muscle: stale'])),
      );
      await pending;
      expect(cubit.state.problems, isEmpty);
      expect(cubit.state.draftChecked, isTrue);
    });

    test('the published findings of an old version are not shown', () async {
      when(() => repository.check(seed))
          .thenAnswer((_) async => const Ok(RulesCheck(findings: [_finding])));
      final cubit = await loadedCubit();
      cubit.setValue(_rest, 165);
      await cubit.review();
      expect(cubit.state.loadedFindings, [_finding]);

      when(() => repository.load()).thenAnswer(
        (_) async => Ok(storedRules(version: 4, rules: seed.set(_rest, 120))),
      );
      await cubit.load();
      expect(cubit.state.loadedFindings, isNull);
    });

    test('closing the cubit cancels the pending check', () {
      fakeAsync((async) {
        final cubit = makeCubit(repository)..load();
        async.flushMicrotasks();
        cubit
          ..setValue(_rest, 165)
          ..close();
        async.elapse(const Duration(seconds: 2));
        verifyNever(() => repository.check(any()));
      });
    });

    test('publish stays publishing until the new version is loaded', () async {
      final draft = seed.set(_rest, 165);
      final reload = Completer<Result<StoredRules>>();
      when(() => repository.publish(any())).thenAnswer((_) async {
        when(() => repository.load()).thenAnswer((_) => reload.future);
        return const Ok(4);
      });
      final cubit = await loadedCubit();
      cubit.setValue(_rest, 165);
      await cubit.review();
      final publishing = cubit.publish('');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.publishing, isTrue);
      expect(cubit.state.canPublish, isFalse);

      reload.complete(Ok(storedRules(version: 4, rules: draft)));
      await publishing;
      expect(cubit.state.publishStatus, PublishStatus.published);
      expect(cubit.state.loaded?.version, 4);
      verify(() => repository.publish(any())).called(1);
    });
  });

  test('the simulator may run the draft once it is changed and checked '
      'without problems', () async {
    final cubit = await loadedCubit();
    expect(cubit.state.runnableDraft, isNull, reason: 'no changes');

    cubit.setValue(_rest, 165);
    expect(cubit.state.runnableDraft, isNull, reason: 'not checked yet');
    await cubit.checkDraft();
    expect(cubit.state.runnableDraft, cubit.state.draft);

    when(() => repository.check(any())).thenAnswer(
      (_) async => const Ok(
        RulesCheck(problems: ['dosing.build_muscle.primary.restS: too long']),
      ),
    );
    cubit.setValue(_rest, 900);
    await cubit.checkDraft();
    expect(cubit.state.runnableDraft, isNull, reason: 'has problems');

    cubit.discard();
    expect(cubit.state.runnableDraft, isNull);
  });
}
