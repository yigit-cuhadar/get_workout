import 'vocabulary.dart';

/// The sets [sets] working sets of one exercise give each of its muscles
/// (SPEC.md, "Volume"): 1 per set for every main muscle, 0.5 for every
/// secondary one. Programs and done workouts count with this alike.
Map<Muscle, double> muscleSets({
  required Iterable<Muscle> main,
  required Iterable<Muscle> secondary,
  required num sets,
}) {
  final result = <Muscle, double>{};
  for (final (muscles, share) in [(main, 1.0), (secondary, 0.5)]) {
    for (final muscle in muscles) {
      result[muscle] = (result[muscle] ?? 0) + sets * share;
    }
  }
  return result;
}

/// Adds [more] to [total], muscle by muscle.
void addMuscleSets(Map<Muscle, double> total, Map<Muscle, double> more) {
  for (final MapEntry(key: muscle, value: sets) in more.entries) {
    total[muscle] = (total[muscle] ?? 0) + sets;
  }
}
