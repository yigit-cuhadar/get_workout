import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_health/forge_health.dart';
import 'package:get_it/get_it.dart';
import 'package:get_workout/features/cardio/cardio_module.dart';
import 'package:get_workout/features/cardio/domain/cardio_repository.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/programs_module.dart';
import 'package:get_workout/features/steps/steps_module.dart';
import 'package:get_workout/features/today/presentation/today_steps_cubit.dart';
import 'package:get_workout/features/today/presentation/today_volume_cubit.dart';
import 'package:get_workout/features/today/presentation/today_week_cubit.dart';
import 'package:get_workout/features/today/today_module.dart';
import 'package:get_workout/features/volume/volume_module.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/workout_module.dart';
import 'package:mocktail/mocktail.dart';

import '../programs/fixtures.dart' show FixedPremium;

class MockAuthRepository extends Mock implements AuthRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockCardioRepository extends Mock implements CardioRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

void main() {
  late GetIt sl;

  setUp(() => sl = GetIt.asNewInstance());
  tearDown(() => sl.reset());

  // A broken or missing registration would otherwise only show when the
  // app opens on Today.
  test('the Today cubits resolve from the real module registrations', () async {
    for (final module in [
      const WorkoutModule(),
      const CardioModule(),
      ProgramsModule(
        completedDays: WorkoutModule.completedDays,
        premium: (_) => const FixedPremium(false),
        showPremium: (_) {},
      ),
      const VolumeModule(),
      HealthModule.fake(FakeHealthSteps()),
      const StepsModule(),
      const TodayModule(),
    ]) {
      module.register(sl);
    }
    // Only what reaches Firebase, or belongs to modules not under test,
    // is replaced.
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => const Stream.empty());
    final catalogue = MockCatalogueCubit();
    when(() => catalogue.state).thenReturn(const CatalogueLoading());
    sl
      ..allowReassignment = true
      ..registerFactory(() => WatchAuthUser(auth))
      ..registerSingleton<ExerciseCatalogueCubit>(catalogue)
      ..registerSingleton<WorkoutRepository>(MockWorkoutRepository())
      ..registerSingleton<CardioRepository>(MockCardioRepository())
      ..registerSingleton<ProgramRepository>(MockProgramRepository());

    final week = sl<TodayWeekCubit>(param1: DateTime.sunday);
    final volume = sl<TodayVolumeCubit>(param1: DateTime.sunday);
    final steps = sl<TodayStepsCubit>();
    expect(week.firstWeekday, DateTime.sunday);
    expect(volume.firstWeekday, DateTime.sunday);
    await steps.load(10000);
    expect(steps.state.status, TodayStepsStatus.setUp);
    await Future.wait([week.close(), volume.close(), steps.close()]);
  });
}
