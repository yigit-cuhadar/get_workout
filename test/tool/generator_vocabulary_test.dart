import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/programs/domain/program.dart';

/// The string list `export const <name> = [...]` of the generator's
/// vocabulary file.
List<String> tsList(String source, String name) {
  final match = RegExp(
    'export const $name = \\[(.*?)\\] as const;',
    dotAll: true,
  ).firstMatch(source);
  expect(match, isNotNull, reason: name);
  return [
    for (final item in RegExp('"([^"]+)"').allMatches(match!.group(1)!))
      item.group(1)!,
  ];
}

int tsInt(String source, String name) => int.parse(
  RegExp('export const $name = (\\d+);').firstMatch(source)!.group(1)!,
);

List<String> codes(List<Coded> values) => [for (final v in values) v.code];

void main() {
  // The server's generator has its own copy of the codes; this holds it
  // equal to the app's.
  final source = File('functions/src/generator/vocabulary.ts')
      .readAsStringSync();

  test('the generator knows the app\'s codes', () {
    expect(tsList(source, 'GOALS'), codes(Goal.values));
    expect(tsList(source, 'LEVELS'), codes(Level.values));
    expect(tsList(source, 'MUSCLES'), codes(Muscle.values));
    expect(tsList(source, 'EQUIPMENT'), codes(Equipment.values));
    expect(tsList(source, 'MOVEMENT_PATTERNS'), codes(MovementPattern.values));
    expect(tsList(source, 'MECHANICS'), codes(Mechanic.values));
    expect(tsList(source, 'GENERATOR_TIERS'), codes(GeneratorTier.values));
    expect(tsList(source, 'SENSITIVE_AREAS'), codes(SensitiveArea.values));
    expect(tsList(source, 'FOCUS_AREAS'), codes(FocusArea.values));
    expect(tsList(source, 'EQUIPMENT_STYLES'), codes(EquipmentStyle.values));
  });

  test('its logging types are the app\'s', () {
    final all = codes(LoggingType.values);
    expect(all, containsAll(tsList(source, 'TIMED_LOGGING_TYPES')));
    expect(tsList(source, 'TIMED_LOGGING_TYPES'), [
      for (final type in LoggingType.values)
        if (type.isDurationBased) type.code,
    ]);
    expect(tsList(source, 'UNLOADED_LOGGING_TYPES'), [
      for (final type in LoggingType.values)
        if (!type.isDurationBased && !type.logsWeight) type.code,
    ]);
  });

  test('its equipment presets are the app\'s', () {
    final block = RegExp(
      r'export const EQUIPMENT_PRESETS[^=]*= \{(.*?)\n\};',
      dotAll: true,
    ).firstMatch(source);
    expect(block, isNotNull);
    final presets = {
      for (final entry in RegExp(
        r'(\w+): \[(.*?)\]',
        dotAll: true,
      ).allMatches(block!.group(1)!))
        entry.group(1)!: {
          for (final item in RegExp('"([^"]+)"').allMatches(entry.group(2)!))
            item.group(1)!,
        },
    };
    expect(presets, {
      for (final profile in EquipmentProfile.values)
        profile.code: {for (final e in profile.equipment) e.code},
    });
  });

  test('its slot roles are the admin panel\'s', () {
    expect(tsList(source, 'SLOT_ROLES'), codes(SlotRole.values));
  });

  test('its days per week are onboarding\'s', () {
    expect(tsInt(source, 'MIN_DAYS'), ProfileLimits.minDaysPerWeek);
    expect(tsInt(source, 'MAX_DAYS'), ProfileLimits.maxDaysPerWeek);
  });
}
