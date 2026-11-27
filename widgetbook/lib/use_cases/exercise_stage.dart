import 'package:flutter/services.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/muscle_model.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/widgets/exercise_stage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

final Future<Model3D> _body = rootBundle
    .load('packages/get_workout/assets/models/body_male.glb')
    .then((data) => Model3D.fromGlb(data.buffer.asUint8List()));

/// The still pair as the page fits it into the stage.
Widget _figures(Model3D? model, List<Muscle> main, List<Muscle> secondary) =>
    Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: FittedBox(
        child: SizedBox(
          width: 320,
          child: MuscleFigures(model: model, main: main, secondary: secondary),
        ),
      ),
    );

Widget _stage(List<Muscle> main, List<Muscle> secondary) => ListView(
  children: [
    FutureBuilder(
      future: _body,
      builder: (context, snapshot) => ExerciseStage(
        main: main,
        secondary: secondary,
        child: _figures(snapshot.data, main, secondary),
      ),
    ),
  ],
);

@widgetbook.UseCase(name: 'Main and secondary', type: ExerciseStage)
Widget exerciseStage(BuildContext context) =>
    _stage(const [Muscle.pec], const [Muscle.frontDelt, Muscle.triceps]);

@widgetbook.UseCase(name: 'Main only', type: ExerciseStage)
Widget exerciseStageMainOnly(BuildContext context) =>
    _stage(const [Muscle.quads], const []);

@widgetbook.UseCase(name: 'Loading', type: ExerciseStage)
Widget exerciseStageLoading(BuildContext context) => ListView(
  children: [
    ExerciseStage(
      main: const [Muscle.pec],
      secondary: const [Muscle.frontDelt, Muscle.triceps],
      child: _figures(
        null,
        const [Muscle.pec],
        const [Muscle.frontDelt, Muscle.triceps],
      ),
    ),
  ],
);
