import 'dart:math' as math;
import 'dart:typed_data';

import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/muscle_model.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/vocabulary.dart';
import '../exercise_motion_cubit.dart';

/// The selected clip of [motion] playing in a loop on a [height] tall
/// stage: the [main] muscles in heat-high, the [secondary] ones in the
/// lighter green, the gear in the palette's greys on a light floor, and a
/// mistake's region ringed in danger. It starts from the recipe's view; one
/// finger turns it, a pinch zooms, and a line under the stage says so. Two
/// buttons in the stage's corner pause and resume the loop and switch half
/// speed; both hold while another clip is picked.
class ExerciseMotionView extends StatefulWidget {
  const ExerciseMotionView({
    super.key,
    required this.motion,
    required this.main,
    required this.secondary,
    required this.height,
  });

  final MotionReady motion;
  final List<Muscle> main;
  final List<Muscle> secondary;
  final double height;

  @override
  State<ExerciseMotionView> createState() => _ExerciseMotionViewState();
}

class _ExerciseMotionViewState extends State<ExerciseMotionView> {
  // The viewer turns the model, so a camera at the recipe's yaw is the
  // model turned the other way.
  late final _camera = ModelViewerController(
    yaw: -widget.motion.motion.view.$1 * math.pi / 180,
    pitch: widget.motion.motion.view.$2 * math.pi / 180,
    // The clip's bounds are fitted as a sphere, which leaves the figure
    // small in a wide card.
    zoom: 1.35,
  );

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  var _playing = true;
  var _slow = false;
  HalfSpeedMotion? _halfSpeed;

  ModelMotion get _played {
    final clip = widget.motion.motion;
    if (!_slow) return clip;
    final halfSpeed = _halfSpeed;
    // A new wrapper restarts the viewer's loop, so it is made once a clip.
    if (halfSpeed != null && halfSpeed.motion == clip) return halfSpeed;
    return _halfSpeed = HalfSpeedMotion(clip);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = ForgeStyle.of(context).colors;
    final gw = GwColors.of(context);
    final viewer = ModelViewer(
      model: widget.motion.model,
      motion: _played,
      playing: _playing,
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
        'floor': p.surfaceSunken,
        'shadow': Color.lerp(p.surfaceSunken, p.lineStrong, 0.6)!,
      },
      groundParts: const {'floor', 'shadow'},
      markerColor: p.danger,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              Positioned.fill(child: viewer),
              Positioned(
                right: Gap.xs,
                bottom: Gap.xs,
                child: Row(
                  spacing: Gap.xs,
                  children: [
                    ForgeIconButton(
                      icon: _playing ? ForgeIcons.pause : ForgeIcons.playArrow,
                      label: _playing ? l10n.motionPause : l10n.motionPlay,
                      variant: ForgeIconButtonVariant.ink,
                      fill: ForgeIconButtonFill.surface,
                      onPressed: () => setState(() => _playing = !_playing),
                    ),
                    ForgeIconButton.text(
                      l10n.motionHalfSpeed,
                      label: l10n.motionHalfSpeedLabel,
                      variant: ForgeIconButtonVariant.ink,
                      fill: ForgeIconButtonFill.surface,
                      toggled: _slow,
                      onPressed: () => setState(() => _slow = !_slow),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Text(
          l10n.motionHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium!
              .copyWith(color: p.inkMuted),
        ),
      ],
    );
  }
}

/// [motion] at half speed: each loop takes twice as long.
class HalfSpeedMotion implements ModelMotion {
  HalfSpeedMotion(this.motion);

  final ModelMotion motion;

  @override
  Duration get duration => motion.duration * 2;

  @override
  Float64List get bounds => motion.bounds;

  @override
  int get jointCount => motion.jointCount;

  @override
  int get markerCount => motion.markerCount;

  @override
  void sample(Duration time, Float32List out) => motion.sample(time ~/ 2, out);

  @override
  void sampleMarkers(Duration time, Float32List out) =>
      motion.sampleMarkers(time ~/ 2, out);
}
