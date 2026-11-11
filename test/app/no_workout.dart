import 'package:bloc_test/bloc_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _IdleWorkoutCubit extends MockCubit<ActiveWorkoutState>
    implements ActiveWorkoutCubit {}

/// Registers a workout cubit with no workout in progress, for the shell's
/// workout bar.
void registerNoWorkout() {
  final cubit = _IdleWorkoutCubit();
  when(() => cubit.state)
      .thenReturn(const ActiveWorkoutState(status: WorkoutStatus.none));
  sl.registerSingleton<ActiveWorkoutCubit>(cubit);
}
