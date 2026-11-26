import 'dart:math' as math;

import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/muscle_model.dart';
import '../../domain/vocabulary.dart';
import '../exercise_motion_cubit.dart';

/// The selected clip of [motion] playing in a loop, filling its parent: the
/// [main] muscles in heat-high, the [secondary] ones in the lighter green,
/// the gear in the palette's greys on a light floor, and a mistake's region
/// ringed in danger. It starts from the recipe's view; one finger turns it,
/// a pinch zooms.
class ExerciseMotionView extends StatefulWidget {
  const ExerciseMotionView({
    super.key,
    required this.motion,
    required this.main,
    required this.secondary,
  });

  final MotionReady motion;
  final List<Muscle> main;
  final List<Muscle> secondary;

  @override
  State<ExerciseMotionView> createState() => _ExerciseMotionViewState();
}

class _ExerciseMotionViewState extends State<ExerciseMotionView> {
  // The viewer turns the model, so a camera at the recipe's yaw is the
  // model turned the other way.
  late final _camera = ModelViewerController(
    yaw: -widget.motion.motion.view.$1 * math.pi / 180,
    pitch: widget.motion.motion.view.$2 * math.pi / 180,
  );

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ForgeStyle.of(context).colors;
    final gw = GwColors.of(context);
    return ModelViewer(
      model: widget.motion.model,
      motion: widget.motion.motion,
      controller: _camera,
      baseColor: muscleModelBase(p),
      partColors: {
        ...muscleMeshColors({
          for (final muscle in widget.secondary) muscle: gw.muscleSecondary,
          for (final muscle in widget.main) muscle: gw.heatHigh,
        }),
        'gear': p.line,
        'steel': p.lineStrong,
        'pad': p.lineStrong,
        'plate': p.inkMuted,
        'floor': p.accentSoft,
        'shadow': Color.lerp(p.accentSoft, p.lineStrong, 0.5)!,
      },
      markerColor: p.danger,
    );
  }
}
