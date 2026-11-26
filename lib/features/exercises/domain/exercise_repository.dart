import 'package:forge_core/forge_core.dart';

import 'exercise.dart';
import 'exercise_animation.dart';

abstract interface class ExerciseRepository {
  /// Emits the live exercises, ordered by popularity: the current list right
  /// away when there is one, then again whenever a sync changes it. Emits
  /// nothing until a list is known; an empty list means an empty catalogue,
  /// never a failure.
  Stream<List<Exercise>> watchExercises();

  /// Brings the list up to date with the server, fetching only what changed
  /// since the last sync. Offline, the list keeps what was synced before and
  /// this returns a [NetworkFailure].
  Future<Result<void>> sync();

  /// The animation of exercise [exerciseId], or null when it has none. Read
  /// through Firestore's cache, so an animation opened once plays offline;
  /// a change on the server shows from the next read on.
  Future<Result<ExerciseAnimation?>> getAnimation(String exerciseId);
}
