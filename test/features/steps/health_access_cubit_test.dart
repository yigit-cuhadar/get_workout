import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';
import 'package:get_workout/features/steps/domain/steps.dart';
import 'package:get_workout/features/steps/domain/steps_usecases.dart';
import 'package:get_workout/features/steps/presentation/health_access_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _GetAccess extends Mock implements GetStepsAccess {}

class _AllowAccess extends Mock implements AllowStepsAccess {}

class _OpenSettings extends Mock implements OpenHealthSettings {}

void main() {
  late _AllowAccess allowAccess;

  setUp(() => allowAccess = _AllowAccess());

  HealthAccessCubit build() =>
      HealthAccessCubit(_GetAccess(), allowAccess, _OpenSettings());

  blocTest<HealthAccessCubit, StepsAccess?>(
    'allow shows what the system answered',
    setUp: () =>
        when(() => allowAccess())
            .thenAnswer((_) async => const Ok(StepsAccess.granted)),
    build: build,
    act: (cubit) => cubit.allow(),
    expect: () => [StepsAccess.granted],
  );

  blocTest<HealthAccessCubit, StepsAccess?>(
    'a failed ask leaves access unknown',
    setUp: () =>
        when(() => allowAccess())
            .thenAnswer((_) async => const Err(UnknownFailure('x'))),
    build: build,
    seed: () => StepsAccess.explain,
    act: (cubit) => cubit.allow(),
    expect: () => [null],
  );
}
