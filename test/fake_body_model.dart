import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise_animation.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_motion_cubit.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:mocktail/mocktail.dart';

class _NoUser extends Mock implements WatchAuthUser {}

class _NoProfile extends Mock implements WatchProfile {}

class _NoAnimation implements GetExerciseAnimation {
  const _NoAnimation();

  @override
  Future<Result<ExerciseAnimation?>> call(String exerciseId) async =>
      const Ok(null);
}

/// A body model that never loads, for screens whose tests skip the model.
BodyModelCubit failingBodyModel() {
  final watchAuthUser = _NoUser();
  when(watchAuthUser.call).thenAnswer((_) => const Stream.empty());
  return BodyModelCubit(
    loadModel: (_) async => throw const FormatException(),
    watchAuthUser: watchAuthUser,
    watchProfile: _NoProfile(),
  );
}

/// Registers an [ExerciseMotionCubit] that finds no animation, for screens
/// whose tests skip exercise animations.
void registerNoMotion() =>
    sl.registerFactoryParam<ExerciseMotionCubit, String, void>(
      (id, _) => ExerciseMotionCubit(
        id,
        getAnimation: const _NoAnimation(),
        body: failingBodyModel(),
        loadRig: (_) async => throw UnimplementedError(),
      ),
    );
