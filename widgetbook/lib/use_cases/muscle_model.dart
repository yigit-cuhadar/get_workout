import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/muscle_heat.dart';
import 'package:get_workout/core/widgets/muscle_model.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

final Future<Model3D> _body = rootBundle
    .load('packages/get_workout/assets/models/body_male.glb')
    .then((data) => Model3D.fromGlb(data.buffer.asUint8List()));

/// [build] with the body model once it has loaded.
Widget _withModel(Widget Function(Model3D model) build) => FutureBuilder(
  future: _body,
  builder: (context, snapshot) => switch (snapshot.data) {
    final model? => build(model),
    null => const MuscleModel.loading(),
  },
);

Widget _panel(Widget child) => Padding(
  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
  child: SizedBox(height: 480, child: child),
);

@widgetbook.UseCase(name: 'Slide and release to open', type: MuscleModel)
Widget muscleModelExplore(BuildContext context) => _panel(
  _withModel(
    (model) =>
        MuscleModel(model: model, onOpen: (_) {}, semanticLabel: 'Body model'),
  ),
);

@widgetbook.UseCase(name: 'Painted by weekly sets', type: MuscleModel)
Widget muscleModelHeat(BuildContext context) => _panel(
  _withModel(
    (model) => MuscleModel(
      model: model,
      onOpen: (_) {},
      semanticLabel: 'Body model',
      sides: false,
      colors: muscleHeatColors(ForgeStyle.of(context).colors, const {
        Muscle.pec: 14,
        Muscle.frontDelt: 22,
        Muscle.midDelt: 22,
        Muscle.quads: 12,
        Muscle.biceps: 6,
        Muscle.abdominal: 4,
      }),
    ),
  ),
);

@widgetbook.UseCase(name: 'Loading', type: MuscleModel)
Widget muscleModelLoading(BuildContext context) =>
    _panel(const MuscleModel.loading());

@widgetbook.UseCase(name: 'Failed', type: MuscleModel)
Widget muscleModelFailed(BuildContext context) =>
    _panel(MuscleModel.failed(onRetry: () {}));

@widgetbook.UseCase(name: 'Front and back side by side', type: MuscleModelPair)
Widget muscleModelPair(BuildContext context) => SingleChildScrollView(
  padding: const EdgeInsets.all(Gap.md),
  child: _withModel(
    (model) => MuscleModelPair(
      model: model,
      title: 'Worked muscles',
      main: const [Muscle.pec],
      secondary: const [Muscle.frontDelt, Muscle.triceps],
    ),
  ),
);

@widgetbook.UseCase(
  name: 'Front and back side by side, loading',
  type: MuscleModelPair,
)
Widget muscleModelPairLoading(BuildContext context) =>
    const SingleChildScrollView(
      padding: EdgeInsets.all(Gap.md),
      child: MuscleModelPair.loading(
        title: 'Worked muscles',
        main: [Muscle.pec],
        secondary: [Muscle.frontDelt, Muscle.triceps],
      ),
    );

@widgetbook.UseCase(
  name: 'Front and back side by side, failed',
  type: MuscleModelPair,
)
Widget muscleModelPairFailed(BuildContext context) => SingleChildScrollView(
  padding: const EdgeInsets.all(Gap.md),
  child: MuscleModelPair.failed(
    title: 'Worked muscles',
    main: const [Muscle.pec],
    secondary: const [Muscle.frontDelt, Muscle.triceps],
    onRetry: () {},
  ),
);
