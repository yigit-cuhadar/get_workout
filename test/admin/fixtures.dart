import 'package:get_workout/admin/exercises/domain/exercise_draft.dart';

/// A valid exercise in the content-file shape.
Map<String, Object?> validJson({
  String id = 'ex_dumbbell_press',
  String name = 'Dumbbell Press',
  String status = 'live',
  int popularity = 1,
  String family = 'dumbbell_press',
  int familyRank = 1,
}) => {
  'id': id,
  'status': status,
  'loggingType': 'weight_reps',
  'mechanic': 'compound',
  'laterality': 'bilateral',
  'level': 'beginner',
  'force': 'push',
  'movementPattern': 'horizontal_push',
  'position': 'supine',
  'grip': 'neutral',
  'equipment': ['dumbbell', 'bench'],
  'equipmentAlternatives': [
    ['kettlebell', 'bench'],
  ],
  'mainMuscles': ['pec'],
  'secondaryMuscles': ['triceps'],
  'family': family,
  'familyRank': familyRank,
  'pinnedAlternatives': <String>[],
  'excludedAlternatives': <String>[],
  'defaultRestS': 90,
  'incrementKg': 2.0,
  'popularity': popularity,
  'l10n': {
    'en': {
      'name': name,
      'aliases': ['$name Alias'],
      'setup': ['Lie on the bench.', 'Hold the weights over the chest.'],
      'execution': ['Lower to the chest.', 'Press back up.'],
      'mistakes': ['Bouncing.', 'Flaring the elbows.'],
      'safety': 'Set the weights down to the sides.',
      'cues': ['Elbows in'],
    },
  },
};

ExerciseRecord record(Map<String, Object?> json, {DateTime? updatedAt}) =>
    ExerciseRecord(json: json, updatedAt: updatedAt ?? DateTime.utc(2026));
