import 'package:bloc_test/bloc_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:get_workout/features/cardio/presentation/cardio_list_cubit.dart';
import 'package:get_workout/features/progress/presentation/progress_body_cubit.dart';
import 'package:get_workout/features/progress/domain/measurement_prompt.dart';
import 'package:get_workout/features/progress/presentation/measurement_prompt_cubit.dart';
import 'package:get_workout/features/progress/presentation/progress_strength_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _BodyCubit extends MockCubit<ProgressBodyState>
    implements ProgressBodyCubit {}

class _StrengthCubit extends MockCubit<ProgressStrengthState>
    implements ProgressStrengthCubit {}

class _PromptCubit extends MockCubit<MeasurementPrompt?>
    implements MeasurementPromptCubit {}

class _CardioListCubit extends MockCubit<CardioListState>
    implements CardioListCubit {}

/// Registers the Progress tab's own cubits as stand-ins, for tests that
/// show the Progress tab without testing its widgets: nothing logged, no
/// strength yet, no measurement prompt and, unless the test has its own, no cardio. Use with
/// `registerTodayStandIns` and `registerBodyListStandIn`.
void registerProgressStandIns() {
  sl
    ..registerFactory<ProgressBodyCubit>(() {
      final cubit = _BodyCubit();
      when(() => cubit.state)
          .thenReturn(const ProgressBodyState(status: BodyListStatus.ready));
      return cubit;
    })
    ..registerFactory<ProgressStrengthCubit>(() {
      final cubit = _StrengthCubit();
      when(() => cubit.state).thenReturn(
        const ProgressStrengthState(status: ProgressStrengthStatus.ready),
      );
      return cubit;
    })
    ..registerFactory<MeasurementPromptCubit>(() {
      final cubit = _PromptCubit();
      when(() => cubit.state).thenReturn(null);
      return cubit;
    });
  if (!sl.isRegistered<CardioListCubit>()) {
    final cardio = _CardioListCubit();
    when(() => cardio.state)
        .thenReturn(const CardioListState(status: CardioListStatus.ready));
    when(() => cardio.firstWeekday).thenReturn(DateTime.sunday);
    sl.registerSingleton<CardioListCubit>(cardio);
  }
}
