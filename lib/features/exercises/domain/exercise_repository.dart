import 'package:forge_core/forge_core.dart';

import 'exercise.dart';

abstract interface class ExerciseRepository {
  /// Emits the live exercises, ordered by popularity: the current list right
  /// away when there is one, then again whenever a sync changes it.
  Stream<List<Exercise>> watchExercises();

  /// Brings the list up to date with the server, fetching only what changed
  /// since the last sync. Offline, the list keeps what was synced before and
  /// this returns a [NetworkFailure].
  Future<Result<void>> sync();
}
