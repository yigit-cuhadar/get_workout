import 'package:flutter/widgets.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../core/widgets/muscle_model.dart';
import '../../domain/vocabulary.dart';

/// The exercise page's stage, edge to edge on the surface: [child] (the
/// animation or the still pair) in a [height] tall box with [overlays] on
/// it, and under it the key to the [main] and [secondary] colours. Without
/// [legend], as while the model has failed, the box stands alone.
class ExerciseStage extends StatelessWidget {
  const ExerciseStage({
    super.key,
    required this.main,
    required this.secondary,
    required this.child,
    this.overlays = const [],
    this.legend = true,
  });

  static const double height = 380;

  final List<Muscle> main;
  final List<Muscle> secondary;
  final Widget child;
  final List<Widget> overlays;
  final bool legend;

  @override
  Widget build(BuildContext context) {
    final p = ForgeStyle.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(child: child),
                ...overlays,
              ],
            ),
          ),
          if (legend)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.md,
                Gap.xs,
                Gap.md,
                Gap.md,
              ),
              child: MuscleLegend(main: main, secondary: secondary),
            ),
        ],
      ),
    );
  }
}
