import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/muscle_meshes.dart';
import '../../domain/vocabulary.dart';
import '../body_model_cubit.dart';
import '../vocabulary_labels.dart';

/// The model from the front and from the back side by side, [main] muscles
/// and [secondary] ones coloured (see [MuscleColors]), taking [heightRatio]
/// of the screen height. Neither view takes gestures, so a page scrolls
/// over them.
class MusclePreview extends StatefulWidget {
  const MusclePreview({
    super.key,
    required this.main,
    this.secondary = const [],
    required this.heightRatio,
  });

  final List<Muscle> main;
  final List<Muscle> secondary;
  final double heightRatio;

  @override
  State<MusclePreview> createState() => _MusclePreviewState();
}

class _MusclePreviewState extends State<MusclePreview> {
  // A viewer without a controller faces the front.
  final _back = ModelViewerController(yaw: math.pi);

  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MuscleColors.of(context);
    final state = context.watch<BodyModelCubit>().state;
    final partColors = {
      for (final muscle in widget.secondary)
        for (final mesh in muscle.meshNames) mesh: colors.secondary,
      for (final muscle in widget.main)
        for (final mesh in muscle.meshNames) mesh: colors.main,
    };
    Widget side(String label, Model3D model, {ModelViewerController? camera}) =>
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: ModelViewer(
                  model: model,
                  controller: camera,
                  interactive: false,
                  partColors: partColors,
                ),
              ),
              Text(label),
            ],
          ),
        );
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * widget.heightRatio,
      child: switch (state) {
        BodyModelLoading() => const LoadingView(),
        BodyModelFailed() => Center(child: Text(l10n.modelLoadFailed)),
        BodyModelReady(:final model) => Semantics(
          label: l10n.detailModelLabel(
            l10n.muscleNames([...widget.main, ...widget.secondary]),
          ),
          image: true,
          excludeSemantics: true,
          child: Row(
            children: [
              side(l10n.detailFront, model),
              side(l10n.detailBack, model, camera: _back),
            ],
          ),
        ),
      },
    );
  }
}

/// Main muscles in the primary colour, secondary ones in a lighter tone of it.
class MuscleColors {
  const MuscleColors(this.main, this.secondary);

  factory MuscleColors.of(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final hsl = HSLColor.fromColor(primary);
    return MuscleColors(
      primary,
      hsl.withLightness(hsl.lightness + (1 - hsl.lightness) * 0.55).toColor(),
    );
  }

  final Color main;
  final Color secondary;
}
