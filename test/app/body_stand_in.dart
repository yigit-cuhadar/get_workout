import 'package:bloc_test/bloc_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/body/presentation/body_list_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _BodyListCubit extends MockCubit<BodyListState>
    implements BodyListCubit {}

/// Registers the shared body list as a stand-in with no entries, for tests
/// that show the Progress tab without testing the body pages.
void registerBodyListStandIn() {
  final cubit = _BodyListCubit();
  when(() => cubit.state)
      .thenReturn(const BodyListState(status: BodyListStatus.ready));
  sl.registerSingleton<BodyListCubit>(cubit);
}
