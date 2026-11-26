import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_motion/forge_motion.dart';
import 'package:get_workout/features/exercises/domain/exercise_animation.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_motion_cubit.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:mocktail/mocktail.dart';

class MockGetExerciseAnimation extends Mock implements GetExerciseAnimation {}

class MockBodyModelCubit extends MockCubit<BodyModelState>
    implements BodyModelCubit {}

Map<String, Object?> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

void main() {
  const id = 'ex_barbell_back_squat';
  final rig = MotionRig.fromJson(_json('assets/models/body_male.rig.json'));
  // One skinned triangle stands in for the body file.
  final body = Model3D.fromMesh(
    partNames: ['body'],
    positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
    normals: Float32List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1]),
    vertexParts: Uint16List(3),
    indices: Uint16List.fromList([0, 1, 2]),
    joints: Uint8List(3),
  );
  // The approved back squat with its mistakes out of catalogue order and
  // the one on line 0 not shown.
  final recipe = _json('content/animations/$id.json');
  final mistakes = [
    for (final mistake in recipe['mistakes']! as List<Object?>)
      mistake! as Map<String, Object?>,
  ];
  final animation = ExerciseAnimation(
    recipe: {
      ...recipe,
      'mistakes': [
        mistakes[2],
        {...mistakes[0], 'shown': false},
        mistakes[1],
      ],
    },
    kits: _json('content/animations/_kits.json'),
  );

  late MockGetExerciseAnimation getAnimation;
  late MockBodyModelCubit bodyModel;

  setUp(() {
    getAnimation = MockGetExerciseAnimation();
    bodyModel = MockBodyModelCubit();
    when(bodyModel.load).thenAnswer((_) async {});
    when(() => getAnimation(id)).thenAnswer((_) async => Ok(animation));
    whenListen(
      bodyModel,
      const Stream<BodyModelState>.empty(),
      initialState: BodyModelReady(body, Sex.male),
    );
  });

  ExerciseMotionCubit build() => ExerciseMotionCubit(
    id,
    getAnimation: getAnimation,
    body: bodyModel,
    loadRig: (sex) async => rig,
  );

  blocTest<ExerciseMotionCubit, ExerciseMotionState>(
    'an exercise without an animation has none',
    setUp: () =>
        when(() => getAnimation(id))
            .thenAnswer((_) async => const Ok<ExerciseAnimation?>(null)),
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [const MotionNone()],
    verify: (_) => verifyNever(bodyModel.load),
  );

  blocTest<ExerciseMotionCubit, ExerciseMotionState>(
    'fails when the animation cannot be read',
    setUp: () =>
        when(() => getAnimation(id))
            .thenAnswer((_) async => const Err(NetworkFailure())),
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [const MotionFailed()],
  );

  blocTest<ExerciseMotionCubit, ExerciseMotionState>(
    'fails when the body cannot load',
    setUp: () => whenListen(
      bodyModel,
      const Stream<BodyModelState>.empty(),
      initialState: const BodyModelFailed(),
    ),
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [const MotionFailed()],
  );

  blocTest<ExerciseMotionCubit, ExerciseMotionState>(
    'plays the correct form first, then the shown mistakes by line',
    build: build,
    act: (cubit) => cubit.load(),
    wait: Duration.zero,
    expect: () => [
      isA<MotionReady>()
          .having((s) => s.clips, 'clips', const [
            AnimationClip.correct(),
            AnimationClip.mistake(2, 1),
            AnimationClip.mistake(0, 2),
          ])
          .having((s) => s.selected, 'selected', 0)
          .having((s) => s.motion.markerCount, 'markers', 0)
          .having(
            (s) => s.model.jointCount == s.motion.jointCount,
            'model joints match the motion',
            isTrue,
          ),
    ],
    verify: (_) => verify(bodyModel.load).called(1),
  );

  blocTest<ExerciseMotionCubit, ExerciseMotionState>(
    'selecting a mistake plays it with its region marked',
    build: build,
    act: (cubit) async {
      await cubit.load();
      await Future<void>.delayed(Duration.zero);
      cubit.select(1);
    },
    skip: 1,
    expect: () => [
      isA<MotionReady>()
          .having((s) => s.selected, 'selected', 1)
          .having((s) => s.motion.markerCount, 'markers', greaterThan(0))
          .having(
            (s) => s.model.jointCount == s.motion.jointCount,
            'model joints match the motion',
            isTrue,
          ),
    ],
  );

  test('the bounds cover the skin around the joints', () async {
    final cubit = build();
    await cubit.load();
    await Future<void>.delayed(Duration.zero);
    final ready = cubit.state as MotionReady;
    final solved = Motion(
      rig: rig,
      kits: animation.kits,
      recipe: animation.recipe,
    );
    for (var axis = 0; axis < 3; axis++) {
      expect(ready.motion.bounds[axis], lessThan(solved.bounds[axis]));
      expect(
        ready.motion.bounds[axis + 3],
        greaterThan(solved.bounds[axis + 3]),
      );
    }
    await cubit.close();
  });
}
