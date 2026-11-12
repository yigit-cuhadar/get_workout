import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/muscle_volume.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/calendar_date.dart';
import '../../workout/domain/workout.dart';

/// The main and secondary muscles of an exercise.
typedef ExerciseMuscles = ({List<Muscle> main, List<Muscle> secondary});

/// The reference band of weekly sets per muscle (SPEC.md, "Volume"). It
/// judges any week of any user, so it does not depend on their level.
abstract final class VolumeBand {
  static const min = 10;
  static const max = 20;
}

/// Where a muscle's weekly sets fall against [VolumeBand], both ends
/// inside.
enum VolumeZone {
  below,
  within,
  above;

  static VolumeZone of(double sets) => sets < VolumeBand.min
      ? below
      : sets > VolumeBand.max
      ? above
      : within;
}

/// One exercise of one finished workout that has working sets.
class VolumeEntry extends Equatable {
  const VolumeEntry({
    required this.workoutId,
    required this.workoutName,
    required this.startedAt,
    required this.exerciseId,
    required this.exerciseName,
    required this.sets,
    required this.muscles,
  });

  final String workoutId;
  final String workoutName;
  final DateTime startedAt;
  final String exerciseId;

  /// As stored with the workout.
  final String exerciseName;

  /// Done sets that are not warm-ups; a drop set is one.
  final int sets;
  final ExerciseMuscles muscles;

  /// What [sets] give each muscle.
  Map<Muscle, double> get perMuscle =>
      muscleSets(main: muscles.main, secondary: muscles.secondary, sets: sets);

  @override
  List<Object?> get props => [
    workoutId,
    workoutName,
    startedAt,
    exerciseId,
    exerciseName,
    sets,
    muscles.main,
    muscles.secondary,
  ];
}

/// What one [VolumeEntry] gave one muscle.
typedef VolumeContribution = ({VolumeEntry entry, double sets});

/// The working sets of one week, which starts on local date [start].
class WeekVolume extends Equatable {
  WeekVolume(this.start, this.entries)
    : sets = {
        for (final MapEntry(:key, :value) in _total(entries).entries)
          if (value > 0) key: value,
      };

  final CalendarDate start;

  /// Oldest first.
  final List<VolumeEntry> entries;

  /// Weekly sets per muscle; a muscle without any is missing.
  final Map<Muscle, double> sets;

  /// The week's last day.
  CalendarDate get end => start.addDays(DateTime.daysPerWeek - 1);

  double setsOf(Muscle muscle) => sets[muscle] ?? 0;

  /// The entries that gave [muscle] sets, oldest first.
  List<VolumeContribution> contributionsTo(Muscle muscle) => [
    for (final entry in entries)
      if (entry.perMuscle[muscle] case final sets? when sets > 0)
        (entry: entry, sets: sets),
  ];

  static Map<Muscle, double> _total(List<VolumeEntry> entries) {
    final total = <Muscle, double>{};
    for (final entry in entries) {
      addMuscleSets(total, entry.perMuscle);
    }
    return total;
  }

  @override
  List<Object?> get props => [start, entries];
}

/// The weeks a trend shows.
const trendWeeks = 12;

/// The [count] weeks from the one starting on [first], oldest first, empty
/// ones included. A workout belongs to the week of the local date it
/// started, like a program day. Only done sets that are not warm-ups
/// count.
///
/// An exercise's muscles are its current ones in [muscles] (the library,
/// custom exercises included), else, for one no longer there, those
/// stored with the workout.
List<WeekVolume> volumeWeeks(
  List<Workout> workouts, {
  required CalendarDate first,
  required int count,
  required Map<String, ExerciseMuscles> muscles,
}) {
  final byWeek = {
    for (var i = 0; i < count; i++)
      first.addDays(DateTime.daysPerWeek * i): <VolumeEntry>[],
  };
  final sorted = [...workouts]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  for (final workout in sorted) {
    final week = CalendarDate.of(workout.startedAt.toLocal())
        .startOfWeek(first.weekday);
    final entries = byWeek[week];
    if (entries == null) continue;
    for (final exercise in workout.exercises) {
      final sets = workingSets(exercise);
      if (sets == 0) continue;
      entries.add(
        VolumeEntry(
          workoutId: workout.id,
          workoutName: workout.name,
          startedAt: workout.startedAt,
          exerciseId: exercise.exerciseId,
          exerciseName: exercise.name,
          sets: sets,
          muscles:
              muscles[exercise.exerciseId] ??
              (
                main: exercise.mainMuscles,
                secondary: exercise.secondaryMuscles,
              ),
        ),
      );
    }
  }
  return [
    for (final MapEntry(:key, :value) in byWeek.entries) WeekVolume(key, value),
  ];
}

/// The sets of [exercise] that count towards volume.
int workingSets(WorkoutExercise exercise) =>
    exercise.sets.where((set) => set.done && !set.isWarmup).length;
