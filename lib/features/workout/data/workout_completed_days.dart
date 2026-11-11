import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';

import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/completed_days.dart';
import 'firestore_workout_repository.dart';

/// The program days done, from the workouts started from them: a day is
/// done on the local date its workout started. Only the date range is
/// queried, which needs no composite index; a week holds few workouts.
class WorkoutCompletedDays implements CompletedDays {
  const WorkoutCompletedDays(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<List<CompletedDay>> watch(
    String uid,
    String programId, {
    required CalendarDate from,
    required CalendarDate to,
  }) => _firestore
      .collection('users/$uid/workouts')
      .where(
        'startedAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(from.toLocalDateTime()),
      )
      .where(
        'startedAt',
        isLessThan: Timestamp.fromDate(to.addDays(1).toLocalDateTime()),
      )
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            if (FirestoreWorkoutRepository.workoutFromMap(doc.id, doc.data())
                case final workout?
                when workout.programId == programId && workout.dayIndex != null)
              CompletedDay(
                date: CalendarDate.of(workout.startedAt.toLocal()),
                dayIndex: workout.dayIndex!,
              ),
        ]..sort((a, b) => a.date.compareTo(b.date)),
      )
      .transform(
        StreamTransformer.fromHandlers(
          handleError: (error, stack, sink) {
            final failure =
                mapFirebaseError(error) ?? UnknownFailure('$error', error);
            Log.e('workout', failure.message, error, stack);
            sink.addError(failure, stack);
          },
        ),
      );
}
