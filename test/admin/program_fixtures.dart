import 'package:get_workout/admin/programs/domain/program_admin_usecases.dart';
import 'package:get_workout/admin/programs/domain/program_draft.dart';

import 'fixtures.dart';

/// Two live exercises a `dumbbells` program can use, and a retired one.
final exerciseRecords = [
  record(validJson()),
  record(validJson(id: 'ex_curl', name: 'Curl', popularity: 2, family: 'curl')),
  record(
    validJson(
      id: 'ex_old_press',
      name: 'Old Press',
      status: 'retired',
      popularity: 3,
      family: 'old_press',
    ),
  ),
];

final exercises = exerciseEntries(exerciseRecords);

/// A valid program in the content-file shape, as a content file holds it,
/// its computed fields included (worked out by hand: day A is 654 s, day
/// B, a superset, 450 s).
Map<String, Object?> programJson({
  String id = 'pr_dumbbell_basics',
  String name = 'Dumbbell Basics',
  String status = 'live',
  bool premium = false,
  int order = 1,
}) => {
  'id': id,
  'status': status,
  'premium': premium,
  'order': order,
  'level': 'beginner',
  'goal': 'build_muscle',
  'equipmentProfile': 'dumbbells',
  'daysPerWeek': 2,
  'lengthWeeks': 8,
  'equipment': ['dumbbell', 'bench'],
  'minutes': {'min': 8, 'max': 11},
  'l10n': {
    'en': {'name': name, 'summary': 'A press and a curl. Twice a week.'},
  },
  'days': [
    {
      'name': 'Day A',
      'items': [
        {
          'exerciseId': 'ex_dumbbell_press',
          'sets': 3,
          'repMin': 8,
          'repMax': 12,
          'restS': 90,
        },
        {
          'exerciseId': 'ex_curl',
          'sets': 3,
          'repMin': 10,
          'repMax': 15,
          'restS': 60,
        },
      ],
    },
    {
      'name': 'Day B',
      'items': [
        {
          'exerciseId': 'ex_curl',
          'sets': 3,
          'repMin': 8,
          'repMax': 12,
          'restS': 0,
          'group': 'A',
        },
        {
          'exerciseId': 'ex_dumbbell_press',
          'sets': 3,
          'repMin': 8,
          'repMax': 12,
          'restS': 90,
          'group': 'A',
        },
      ],
    },
  ],
};

ProgramRecord programRecord(
  Map<String, Object?> json, {
  DateTime? card,
  DateTime? detail,
}) => ProgramRecord(
  json: json,
  version: (
    card: card ?? DateTime.utc(2026),
    detail: detail ?? DateTime.utc(2026),
  ),
);

/// [json] without its days, as the list reads a card.
Map<String, Object?> cardOf(Map<String, Object?> json) =>
    Map.of(json)..remove('days');
