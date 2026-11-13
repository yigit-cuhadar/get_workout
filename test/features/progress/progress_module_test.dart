import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:get_it/get_it.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/progress/presentation/progress_body_cubit.dart';
import 'package:get_workout/features/progress/presentation/progress_month_cubit.dart';
import 'package:get_workout/features/progress/presentation/progress_strength_cubit.dart';
import 'package:get_workout/features/progress/progress_module.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockBodyListCubit extends MockCubit<BodyListState>
    implements BodyListCubit {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

void main() {
  // A broken or missing registration would otherwise only show when the
  // Progress tab opens.
  test('the Progress cubits resolve from the module', () async {
    final sl = GetIt.asNewInstance();
    const ProgressModule().register(sl);
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => const Stream.empty());
    final catalogue = MockCatalogueCubit();
    when(() => catalogue.state).thenReturn(const CatalogueLoading());
    final bodyList = MockBodyListCubit();
    when(() => bodyList.state).thenReturn(const BodyListState());
    sl
      ..registerFactory(() => WatchAuthUser(auth))
      ..registerSingleton<ExerciseCatalogueCubit>(catalogue)
      ..registerSingleton<BodyListCubit>(bodyList)
      ..registerSingleton<WorkoutRepository>(MockWorkoutRepository());

    final strength = sl<ProgressStrengthCubit>();
    final month = sl<ProgressMonthCubit>();
    final body = sl<ProgressBodyCubit>();
    expect(body.state, const ProgressBodyState());
    expect(strength.state, const ProgressStrengthState());
    expect(month.state.status, ProgressMonthStatus.loading);
    await Future.wait([
      strength.close(),
      month.close(),
      body.close(),
      sl.reset(),
    ]);
  });
}
