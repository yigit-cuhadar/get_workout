import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../exercise_catalogue_cubit.dart';
import '../exercise_motion_cubit.dart';

/// A round play button for exercise [exerciseId] when it has an animation,
/// and nothing otherwise. It opens the exercise's page at [detailRoute],
/// where the animation plays.
class ExerciseMotionButton extends StatelessWidget {
  const ExerciseMotionButton({
    super.key,
    required this.exerciseId,
    required this.detailRoute,
  });

  final String exerciseId;
  final String detailRoute;

  @override
  Widget build(BuildContext context) {
    final custom = context.select(
      (ExerciseCatalogueCubit cubit) => switch (cubit.state) {
        CatalogueReady(:final exercises) =>
          exercises.where((e) => e.id == exerciseId).firstOrNull?.isCustom,
        _ => null,
      },
    );
    if (custom != false) return const SizedBox.shrink();
    return BlocProvider(
      create: (_) => sl<ExerciseMotionCubit>(param1: exerciseId)..load(),
      child: BlocBuilder<ExerciseMotionCubit, ExerciseMotionState>(
        buildWhen: (before, after) =>
            (before is MotionReady) != (after is MotionReady),
        builder: (context, state) => state is MotionReady
            ? ForgeIconButton(
                icon: ForgeIcons.playArrow,
                label: AppLocalizations.of(context).motionWatch,
                variant: ForgeIconButtonVariant.ink,
                fill: ForgeIconButtonFill.sunken,
                onPressed: () => context.push(detailRoute),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
