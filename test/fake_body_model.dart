import 'package:forge_auth/forge_auth.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:mocktail/mocktail.dart';

class _NoUser extends Mock implements WatchAuthUser {}

class _NoProfile extends Mock implements WatchProfile {}

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
