import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/user_stream_follower.dart';
import '../domain/exercise_usecases.dart';

class ExerciseNotesState extends Equatable {
  const ExerciseNotesState(this.notes);

  /// By exercise id.
  final Map<String, String> notes;

  String? of(String exerciseId) => notes[exerciseId];

  @override
  List<Object?> get props => [notes];
}

/// The own notes on exercises of whoever is signed in. Empty until the
/// current user's notes arrive, also after every user change.
class ExerciseNotesCubit extends Cubit<ExerciseNotesState> {
  ExerciseNotesCubit({
    required WatchAuthUser watchAuthUser,
    required WatchExerciseNotes watchExerciseNotes,
    required this._setExerciseNote,
    Duration retryDelay = const Duration(seconds: 1),
  }) : super(const ExerciseNotesState({})) {
    _follower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchExerciseNotes.call,
      // Never show the previous user's notes.
      onUser: (_) {
        const reset = ExerciseNotesState({});
        if (state != reset) emit(reset);
      },
      onData: (notes) => emit(ExerciseNotesState(notes)),
      logTag: 'exerciseNotes',
      retryDelay: retryDelay,
    );
  }

  final SetExerciseNote _setExerciseNote;
  late final UserStreamFollower<Map<String, String>> _follower;

  /// Stores [note] on [exerciseId]; a blank one removes it. The change
  /// shows up through the notes stream (at once, from Firestore's local
  /// cache). Returns the failure, if any.
  Future<Failure?> save(String exerciseId, String note) async {
    final uid = _follower.uid;
    if (uid == null) return const UnknownFailure('Signed out');
    _follower.resume();
    final result = await _setExerciseNote((
      uid: uid,
      exerciseId: exerciseId,
      note: note,
    ));
    return result.failureOrNull;
  }

  @override
  Future<void> close() async {
    await _follower.cancel();
    return super.close();
  }
}
