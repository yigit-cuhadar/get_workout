import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _IdleWorkoutCubit extends MockCubit<ActiveWorkoutState>
    implements ActiveWorkoutCubit {}

/// A workout cubit with no workout in progress, for the shell's workout
/// bar.
BlocProvider<ActiveWorkoutCubit> noWorkout() {
  final cubit = _IdleWorkoutCubit();
  when(() => cubit.state)
      .thenReturn(const ActiveWorkoutState(status: WorkoutStatus.none));
  return BlocProvider<ActiveWorkoutCubit>.value(value: cubit);
}
