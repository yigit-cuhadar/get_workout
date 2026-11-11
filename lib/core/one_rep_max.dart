/// Sets above this many reps estimate a one-rep max too loosely to use.
const maxEpleyReps = 12;

/// Epley, `weight * (1 + reps / 30)`; a single rep is the weight itself.
/// Null for no weight, fewer than one rep or more than [maxEpleyReps].
double? epleyOneRepMax(double weightKg, int reps) {
  if (!(weightKg > 0) || reps < 1 || reps > maxEpleyReps) return null;
  return reps == 1 ? weightKg : weightKg * (1 + reps / 30);
}
