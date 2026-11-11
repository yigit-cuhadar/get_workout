import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockModel3D extends Mock implements Model3D {}

void main() {
  final model = MockModel3D();

  test('loads nothing until asked', () {
    var loads = 0;
    final cubit = BodyModelCubit(() async {
      loads++;
      return model;
    });
    expect(cubit.state, const BodyModelLoading());
    expect(loads, 0);
  });

  var loads = 0;
  blocTest<BodyModelCubit, BodyModelState>(
    'loads once, however often it is asked',
    setUp: () => loads = 0,
    build: () => BodyModelCubit(() async {
      loads++;
      return model;
    }),
    act: (cubit) async {
      await Future.wait([cubit.load(), cubit.load()]);
      await cubit.load();
    },
    expect: () => [BodyModelReady(model)],
    verify: (_) => expect(loads, 1),
  );

  var attempts = 0;
  blocTest<BodyModelCubit, BodyModelState>(
    'a failure can be retried',
    setUp: () => attempts = 0,
    build: () => BodyModelCubit(() async {
      if (++attempts == 1) throw const FormatException('broken glb');
      return model;
    }),
    act: (cubit) async {
      await cubit.load();
      await cubit.load();
    },
    expect: () => [
      const BodyModelFailed(),
      const BodyModelLoading(),
      BodyModelReady(model),
    ],
  );
}
